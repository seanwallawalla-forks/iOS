//
//  TabSwitcherViewController.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import UIKit
import Core
import WebKit
import os.log

// swiftlint:disable file_length
class TabSwitcherViewController: UIViewController {
    
    struct Constants {
        static let preferredMinNumberOfRows: CGFloat = 2.7

        static let cellMinHeight: CGFloat = 140.0
        static let cellMaxHeight: CGFloat = 209.0
    }

    typealias BookmarkAllResult = (newBookmarksCount: Int, existingBookmarksCount: Int)
    
    @IBOutlet weak var titleView: UILabel!
    @IBOutlet weak var collectionView: UICollectionView!
    
    // @IBOutlet weak var displayModeButton: UIButton!
    @IBOutlet weak var bookmarkAllButton: UIButton!
    
    @IBOutlet weak var fireButton: UIBarButtonItem!
    @IBOutlet weak var doneButton: UIBarButtonItem!
    @IBOutlet weak var plusButton: UIBarButtonItem!
    
    @IBOutlet weak var topFireButton: UIButton!
    @IBOutlet weak var topPlusButton: UIButton!
    @IBOutlet weak var topDoneButton: UIButton!

    @IBOutlet weak var logoImage: UIImageView!
    @IBOutlet weak var searchBackground: UIView!
    @IBOutlet weak var omniBarContainer: UIView!
    weak var omniBar: OmniBar?

    // @IBOutlet var displayModeTrailingConstraint: NSLayoutConstraint!

    weak var delegate: TabSwitcherDelegate?
    weak var previewsSource: TabPreviewsSource?
    weak var tabsModel: TabsModel!

    weak var reorderGestureRecognizer: UIGestureRecognizer?
    
    override var canBecomeFirstResponder: Bool { return true }
    
    var currentSelection: Int?
    lazy var bookmarksManager: BookmarksManager = BookmarksManager()

    private var tabSwitcherSettings: TabSwitcherSettings = DefaultTabSwitcherSettings()
    private var isProcessingUpdates = false

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.register(UINib(nibName: "FavoriteHomeCell", bundle: nil), forCellWithReuseIdentifier: "favorite")

        setupSearch()

        refreshTitle()
        setupBackgroundView()
        currentSelection = tabsModel.currentTab != nil ? tabsModel.indexOf(tab: tabsModel.currentTab!) : nil
        applyTheme(ThemeManager.shared.currentTheme)
        becomeFirstResponder()
        
        if !tabSwitcherSettings.hasSeenNewLayout {
            Pixel.fire(pixel: .tabSwitcherNewLayoutSeen)
            tabSwitcherSettings.hasSeenNewLayout = true
        }
        
        if #available(iOS 13.4, *) {
            // displayModeButton.isPointerInteractionEnabled = true
            bookmarkAllButton.isPointerInteractionEnabled = true
            topFireButton.isPointerInteractionEnabled = true
            topPlusButton.isPointerInteractionEnabled = true
            topDoneButton.isPointerInteractionEnabled = true
        }

        // collectionView.isHidden = true
        // collectionView.blur(style: .regular)
    }

    func setupSearch() {
        let omniBar = OmniBar.loadFromXib()
        omniBar.omniDelegate = self
        omniBar.frame = omniBarContainer.bounds
        omniBarContainer.addSubview(omniBar)
        self.omniBar = omniBar
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        topFireButton.isHidden = !AppWidthObserver.shared.isLargeWidth
        topDoneButton.isHidden = !AppWidthObserver.shared.isLargeWidth
        topPlusButton.isHidden = !AppWidthObserver.shared.isLargeWidth
    }
    
    private func setupBackgroundView() {
        // TODO a nice matt anderson background?
    }
    
    private func refreshDisplayModeButton(displayModeButton: UIButton, theme: Theme = ThemeManager.shared.currentTheme) {
        switch theme.currentImageSet {
        case .dark:
            // Reverse colors (selection)
            if tabSwitcherSettings.isGridViewEnabled {
                displayModeButton.setImage(UIImage(named: "TabsToggleList"), for: .normal)
            } else {
                displayModeButton.setImage(UIImage(named: "TabsToggleGrid"), for: .normal)
            }
        case .light:
            if tabSwitcherSettings.isGridViewEnabled {
                displayModeButton.setImage(UIImage(named: "TabsToggleGrid"), for: .normal)
            } else {
                displayModeButton.setImage(UIImage(named: "TabsToggleList"), for: .normal)
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if reorderGestureRecognizer == nil {
            let recognizer = UILongPressGestureRecognizer(target: self,
                                                          action: #selector(handleLongPress(gesture:)))
            collectionView.addGestureRecognizer(recognizer)
            reorderGestureRecognizer = recognizer
        }
    }
    
    func prepareForPresentation() {
        view.layoutIfNeeded()
        self.scrollToInitialTab()
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

        if segue.destination.children.count > 0,
            let controller = segue.destination.children[0] as? BookmarksViewController {
            controller.delegate = self
            return
        }
        
    }

    @objc func handleLongPress(gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let path = collectionView.indexPathForItem(at: gesture.location(in: collectionView)) else { return }
            collectionView.beginInteractiveMovementForItem(at: path)
            
        case .changed:
            collectionView.updateInteractiveMovementTargetPosition(gesture.location(in: collectionView))
            
        case .ended:
            collectionView.endInteractiveMovement()
            
        default:
            collectionView.cancelInteractiveMovement()
        }
        
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    private func scrollToInitialTab() {
        guard let index = tabsModel.currentTab == nil ? 0 : tabsModel.indexOf(tab: tabsModel.currentTab!) else { return }
        guard index < collectionView.numberOfItems(inSection: 0) else { return }
        let indexPath = IndexPath(row: index, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: false)
    }

    private func refreshTitle() {
        titleView.text = UserText.numberOfTabs(tabsModel.count)
    }
    
    fileprivate func displayBookmarkAllStatusToast(with results: BookmarkAllResult, openTabsCount: Int) {
        if results.newBookmarksCount == openTabsCount {
            view.showBottomToast(UserText.bookmarkAllTabsSaved)
        } else {
            let failedToSaveCount = openTabsCount - results.newBookmarksCount - results.existingBookmarksCount
            os_log("Failed to save %d tabs", log: generalLog, type: .debug, failedToSaveCount)
            view.showBottomToast(UserText.bookmarkAllTabsFailedToSave)
        }
    }
    
    fileprivate func bookmarkAll() -> BookmarkAllResult {
        
        let bookmarksManager = BookmarksManager()
        var newBookmarksCount: Int = 0
        var existingBookmarksCount: Int = 0
        
        tabsModel.forEach { tab in
            if let link = tab.link {
                if bookmarksManager.contains(url: link.url) {
                    existingBookmarksCount += 1
                } else {
                    bookmarksManager.save(bookmark: link)
                    newBookmarksCount += 1
                }
            } else {
                os_log("no valid link found for tab %s", log: generalLog, type: .debug, String(describing: tab))
            }
        }
        
        return (newBookmarksCount: newBookmarksCount, existingBookmarksCount: existingBookmarksCount)
    }

    @IBAction func onBookmarkAllOpenTabsPressed(_ sender: UIButton) {
         
        let alert = UIAlertController(title: UserText.alertBookmarkAllTitle,
                                      message: UserText.alertBookmarkAllMessage,
                                      preferredStyle: .alert)
        alert.overrideUserInterfaceStyle()
        alert.addAction(UIAlertAction(title: UserText.actionCancel, style: .cancel))
        alert.addAction(title: UserText.actionBookmark, style: .default) {
            let savedState = self.bookmarkAll()
            self.displayBookmarkAllStatusToast(with: savedState, openTabsCount: self.tabsModel.count)
        }
        
        present(alert, animated: true, completion: nil)
    }
    
    @IBAction func onDisplayModeButtonPressed(_ sender: UIButton) {
        tabSwitcherSettings.isGridViewEnabled = !tabSwitcherSettings.isGridViewEnabled
        
        if tabSwitcherSettings.isGridViewEnabled {
            Pixel.fire(pixel: .tabSwitcherGridEnabled)
        } else {
            Pixel.fire(pixel: .tabSwitcherListEnabled)
        }
        
        UIView.transition(with: view,
                          duration: 0.3,
                          options: .transitionCrossDissolve, animations: {
                            self.collectionView.reloadData()
        }, completion: nil)
    }

    @IBAction func onAddPressed(_ sender: UIBarButtonItem) {
        delegate?.tabSwitcherDidRequestNewTab(tabSwitcher: self)
        
        // Delay dismissal so new tab inertion can be animated.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.dismiss()
        }
    }

    @IBAction func onDonePressed(_ sender: UIBarButtonItem) {
        dismiss()
    }
    
    func markCurrentAsViewedAndDismiss() {
        if let current = currentSelection {
            let tab = tabsModel.get(tabAt: current)
            tab.viewed = true
            tabsModel.save()
            delegate?.tabSwitcher(self, didSelectTab: tab)
        }
        dismiss()
    }

    @IBAction func onFirePressed(sender: AnyObject) {
        Pixel.fire(pixel: .forgetAllPressedTabSwitching)
        
        let alert = ForgetDataAlert.buildAlert(forgetTabsAndDataHandler: { [weak self] in
            self?.forgetAll()
        })
        
        if let anchor = sender as? UIView {
            self.present(controller: alert, fromView: anchor)
        } else {
            self.present(controller: alert, fromView: view)
        }
    }

    private func forgetAll() {
        self.delegate?.tabSwitcherDidRequestForgetAll(tabSwitcher: self)
    }

    func dismiss() {
        dismiss(animated: true, completion: nil)
    }
}

extension TabSwitcherViewController: TabViewCellDelegate {

    func deleteTab(tab: Tab) {
        tabsModel.remove(tab: tab)
        tabsModel.save()
        collectionView.reloadData()
//        guard let index = tabsModel.indexOf(tab: tab) else { return }
//        let currentIndex = tabsModel.currentTab != nil ? tabsModel.indexOf(tab: tabsModel.currentTab!) : nil
//
//        let isLastTab = tabsModel.count == 1
//        if isLastTab {
//            delegate?.tabSwitcher(self, didRemoveTab: tab)
//            currentSelection = currentIndex
//            refreshTitle()
//            collectionView.reloadData()
//        } else {
//            collectionView.performBatchUpdates({
//                isProcessingUpdates = true
//                delegate?.tabSwitcher(self, didRemoveTab: tab)
//                currentSelection = currentIndex
//                collectionView.deleteItems(at: [IndexPath(row: index, section: 0)])
//            }, completion: { _ in
//                self.isProcessingUpdates = false
//                guard let current = self.currentSelection else { return }
//                self.refreshTitle()
//                self.collectionView.reloadItems(at: [IndexPath(row: current, section: 0)])
//            })
//        }
    }
    
    func isCurrent(tab: Tab) -> Bool {
        return currentSelection == tabsModel.indexOf(tab: tab)
    }

}

extension TabSwitcherViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 3
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch section {
        case 0: return PinnedSiteStore.shared.count
        case 1: return bookmarksManager.favoritesCount
        case 2: return tabsModel.count
        default: fatalError("Unexpected section \(section)")
        }
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        switch indexPath.section {
        case 0:
            return pinnedSiteCell(atIndexPath: indexPath)

        case 1:
            return favoriteCell(atIndexPath: indexPath)

        case 2:
            return tabCell(atIndexPath: indexPath)

        default: fatalError()
        }
    }

    func pinnedSiteCell(atIndexPath indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "favorite", for: indexPath) as? FavoriteHomeCell else {
            fatalError("Failed to dequeue cell favorite as FavoriteHomeCell")
        }
        guard let host = PinnedSiteStore.shared.pinnedSite(at: indexPath.row) else { fatalError() }
        cell.decorate(with: ThemeManager.shared.currentTheme)
        cell.updateFor(link: Link(title: host, url: URL(string: "https://\(host)")!))
        return cell
    }

    func favoriteCell(atIndexPath indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "favorite", for: indexPath) as? FavoriteHomeCell else {
            fatalError("Failed to dequeue cell favorite as FavoriteHomeCell")
        }
        cell.decorate(with: ThemeManager.shared.currentTheme)
        cell.updateFor(link: bookmarksManager.favorite(atIndex: indexPath.row)!)
        return cell
    }

    func tabCell(atIndexPath indexPath: IndexPath) -> UICollectionViewCell {
        let cellIdentifier = tabSwitcherSettings.isGridViewEnabled ? TabViewGridCell.reuseIdentifier : TabViewListCell.reuseIdentifier
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellIdentifier, for: indexPath) as? TabViewCell else {
            fatalError("Failed to dequeue cell \(cellIdentifier) as TabViewCell")
        }
        cell.delegate = self
        cell.isDeleting = false

        if indexPath.row < tabsModel.count {
            let tab = tabsModel.get(tabAt: indexPath.row)
            // tab.addObserver(self)
            cell.update(withTab: tab,
                        preview: previewsSource?.preview(for: tab),
                        reorderRecognizer: reorderGestureRecognizer)
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath)
        -> UICollectionReusableView {
        guard let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: indexPath)
                as? TabSwitcherHeaderCell else {
            fatalError("Unable to cast header cell")
        }

        header.displayModeButton.isHidden = true
        header.fireButton.isHidden = true
        header.bookmarksButton.isHidden = true

        switch indexPath.section {

        case 0:
            header.label.text = "Pinned Sites"

        case 1:
            header.label.text = "Favorites"
            header.bookmarksButton.isHidden = false
            header.bookmarksButton.tintColor = ThemeManager.shared.currentTheme.barTintColor

        case 2:
            header.label.text = "Tabs"
            header.displayModeButton.isHidden = false
            header.fireButton.isHidden = false
            header.fireButton.tintColor = ThemeManager.shared.currentTheme.barTintColor
            refreshDisplayModeButton(displayModeButton: header.displayModeButton)

        default: fatalError("Unexpected section \(indexPath.section)")

        }

        return header
    }

}

extension TabSwitcherViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

        switch indexPath.section {
        case 0:
            guard let host = PinnedSiteStore.shared.pinnedSite(at: indexPath.row) else { fatalError() }
            dismiss()
            (presentingViewController as? MainViewController)?.launchPinnedSite(host)

        case 1:
            let link = bookmarksManager.favorite(atIndex: indexPath.row)!
            launchLinkInNewTab(link)

        case 2:
            currentSelection = indexPath.row
            markCurrentAsViewedAndDismiss()

        default: fatalError()

        }

    }

    func launchLinkInNewTab(_ link: Link) {
        dismiss()
        (presentingViewController as? MainViewController)?.loadUrlInNewTab(link.url, reuseExisting: true)
    }
   
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
                        toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
        return proposedIndexPath
    }
    
    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        tabsModel.moveTab(from: sourceIndexPath.row, to: destinationIndexPath.row)
        currentSelection = tabsModel.currentTab != nil ? tabsModel.indexOf(tab: tabsModel.currentTab!) : nil
    }

}

extension TabSwitcherViewController: UICollectionViewDelegateFlowLayout {

    private func calculateColumnWidth(minimumColumnWidth: CGFloat, maxColumns: Int) -> CGFloat {
        // Spacing is supposed to be equal between cells and on left/right side of the collection view
        let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
        let spacing = layout?.sectionInset.left ?? 0.0
        
        let contentWidth = collectionView.bounds.width - spacing
        let numberOfColumns = min(maxColumns, Int(contentWidth / minimumColumnWidth))
        return contentWidth / CGFloat(numberOfColumns) - spacing
    }
    
    private func calculateRowHeight(columnWidth: CGFloat) -> CGFloat {
        
        // Calculate height based on the view size
        let contentAspectRatio = collectionView.bounds.width / collectionView.bounds.height
        let heightToFit = (columnWidth / contentAspectRatio) + TabViewGridCell.Constants.cellHeaderHeight
        
        // Try to display at least `preferredMinNumberOfRows`
        let preferredMaxHeight = collectionView.bounds.height / Constants.preferredMinNumberOfRows
        let preferredHeight = min(preferredMaxHeight, heightToFit)
        
        return min(Constants.cellMaxHeight,
                   max(Constants.cellMinHeight, preferredHeight))
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {

        guard 2 == indexPath.section else {
            return .init(width: 68, height: 110)
        }

        if tabSwitcherSettings.isGridViewEnabled {
            let columnWidth = calculateColumnWidth(minimumColumnWidth: 150, maxColumns: 4)
            let rowHeight = calculateRowHeight(columnWidth: columnWidth)
            return CGSize(width: floor(columnWidth),
                          height: floor(rowHeight))
        } else {
            let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
            let spacing = layout?.sectionInset.left ?? 0.0
            
            let width = min(664, collectionView.bounds.size.width - 2 * spacing)
            
            return CGSize(width: width, height: 70)
        }
    }
    
}

extension TabSwitcherViewController: TabObserver {
    
    func didChange(tab: Tab) {
        // Reloading when updates are processed will result in a crash
        guard !isProcessingUpdates else { return }
        
        if let index = tabsModel.indexOf(tab: tab) {
            collectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
        }
    }
}

extension TabSwitcherViewController: Themable {
    
    func decorate(with theme: Theme) {
        view.backgroundColor = theme.backgroundColor

        searchBackground.backgroundColor = theme.barBackgroundColor
        omniBar?.decorate(with: theme)
        // logoImage.image = theme.currentImageSet == .dark ? UIImage(named: "LogoLightText") : UIImage(named: "LogoDarkText")

        titleView.textColor = theme.barTintColor
        bookmarkAllButton.tintColor = theme.barTintColor
        topDoneButton.tintColor = theme.barTintColor
        topPlusButton.tintColor = theme.barTintColor
        topFireButton.tintColor = theme.barTintColor

        collectionView.reloadData()

    }
}

extension TabSwitcherViewController: OmniBarDelegate {

    func onOmniQueryUpdated(_ query: String) {
        print("***", #function)
    }

    func onOmniQuerySubmitted(_ query: String) {
        print("***", #function)
        dismiss()
        (presentingViewController as? MainViewController)?.loadQueryInNewTab(query, reuseExisting: true)
    }

    func onDismissed() {
        print("***", #function)
    }

    func onSiteRatingPressed() {
        print("***", #function)
    }

    func onMenuPressed() {
        print("***", #function)
    }

    func onBookmarksPressed() {
        print("***", #function)
    }

    func onSettingsPressed() {
        print("***", #function)
    }

    func onCancelPressed() {
        print("***", #function)
        omniBar?.resignFirstResponder()
    }

    func onEnterPressed() {
        print("***", #function)
    }

    func onRefreshPressed() {
        print("***", #function)
    }

    func onBackPressed() {
        print("***", #function)
    }

    func onForwardPressed() {
        print("***", #function)
    }

    func onSharePressed() {
        print("***", #function)
    }

    func onTextFieldWillBeginEditing(_ omniBar: OmniBar) {
        print("***", #function)
    }

    // Returns whether field should select the text or not
    func onTextFieldDidBeginEditing(_ omniBar: OmniBar) -> Bool {
        print("***", #function)
        return false
    }

}

extension TabSwitcherViewController: BookmarksDelegate {

    func bookmarksDidSelect(link: Link) {
        launchLinkInNewTab(link)
    }

    func bookmarksUpdated() {
        collectionView.reloadData()
    }

}

class TabSwitcherHeaderCell: UICollectionReusableView {

    @IBOutlet var label: UILabel!
    @IBOutlet var displayModeButton: UIButton!
    @IBOutlet var fireButton: UIButton!
    @IBOutlet var bookmarksButton: UIButton!

}

// swiftlint:enable file_length
