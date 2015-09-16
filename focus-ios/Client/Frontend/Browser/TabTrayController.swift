/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import SnapKit

struct TabTrayControllerUX {
    static let CornerRadius = CGFloat(4.0)
    static let BackgroundColor = UIConstants.AppBackgroundColor
    static let CellBackgroundColor = UIColor(red:0.95, green:0.95, blue:0.95, alpha:1)
    static let TextBoxHeight = CGFloat(32.0)
    static let FaviconSize = CGFloat(18.0)
    static let Margin = CGFloat(15)
    static let ToolbarBarTintColor = UIConstants.AppBackgroundColor
    static let ToolbarButtonOffset = CGFloat(10.0)
    static let TabTitleTextFont = UIConstants.DefaultSmallFontBold
    static let CloseButtonSize = CGFloat(18.0)
    static let CloseButtonMargin = CGFloat(6.0)
    static let CloseButtonEdgeInset = CGFloat(10)

    static let NumberOfColumnsThin = 1
    static let NumberOfColumnsWide = 3
    static let CompactNumberOfColumnsThin = 2

    // Moved from UIConstants temporarily until animation code is merged
    static var StatusBarHeight: CGFloat {
        if UIScreen.mainScreen().traitCollection.verticalSizeClass == .Compact {
            return 0
        }
        return 20
    }
}

struct LightTabCellUX {
    static let TabTitleTextColor = UIColor.blackColor()
}

struct DarkTabCellUX {
    static let TabTitleTextColor = UIColor.whiteColor()
}

protocol TabCellDelegate: class {
    func tabCellDidClose(cell: TabCell)
}

class TabCell: UICollectionViewCell {
    enum Style {
        case Light
        case Dark
    }

    static let Identifier = "TabCellIdentifier"

    var style: Style = .Light {
        didSet {
            applyStyle(style)
        }
    }

    let backgroundHolder = UIView()
    let background = UIImageViewAligned()
    let titleText: UILabel
    let innerStroke: InnerStrokedView
    let favicon: UIImageView = UIImageView()
    let closeButton: UIButton

    var title: UIVisualEffectView!
    var animator: SwipeAnimator!

    weak var delegate: TabCellDelegate?

    // Changes depending on whether we're full-screen or not.
    var margin = CGFloat(0)

    override init(frame: CGRect) {
        self.backgroundHolder.backgroundColor = UIColor.whiteColor()
        self.backgroundHolder.layer.cornerRadius = TabTrayControllerUX.CornerRadius
        self.backgroundHolder.clipsToBounds = true
        self.backgroundHolder.backgroundColor = TabTrayControllerUX.CellBackgroundColor

        self.background.contentMode = UIViewContentMode.ScaleAspectFill
        self.background.clipsToBounds = true
        self.background.userInteractionEnabled = false
        self.background.alignLeft = true
        self.background.alignTop = true

        self.favicon.backgroundColor = UIColor.clearColor()
        self.favicon.layer.cornerRadius = 2.0
        self.favicon.layer.masksToBounds = true

        self.titleText = UILabel()
        self.titleText.textAlignment = NSTextAlignment.Left
        self.titleText.userInteractionEnabled = false
        self.titleText.numberOfLines = 1
        self.titleText.font = TabTrayControllerUX.TabTitleTextFont

        self.closeButton = UIButton()
        self.closeButton.setImage(UIImage(named: "stop"), forState: UIControlState.Normal)
        self.closeButton.imageEdgeInsets = UIEdgeInsetsMake(TabTrayControllerUX.CloseButtonEdgeInset, TabTrayControllerUX.CloseButtonEdgeInset, TabTrayControllerUX.CloseButtonEdgeInset, TabTrayControllerUX.CloseButtonEdgeInset)

        self.innerStroke = InnerStrokedView(frame: self.backgroundHolder.frame)
        self.innerStroke.layer.backgroundColor = UIColor.clearColor().CGColor

        super.init(frame: frame)

        self.opaque = true

        self.animator = SwipeAnimator(animatingView: self.backgroundHolder, container: self)
        self.closeButton.addTarget(self.animator, action: "SELcloseWithoutGesture", forControlEvents: UIControlEvents.TouchUpInside)

        contentView.addSubview(backgroundHolder)
        backgroundHolder.addSubview(self.background)
        backgroundHolder.addSubview(innerStroke)

        // Default style is light
        applyStyle(style)

        self.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: NSLocalizedString("Close", comment: "Accessibility label for action denoting closing a tab in tab list (tray)"), target: self.animator, selector: "SELcloseWithoutGesture")
        ]
    }

    private func applyStyle(style: Style) {
        self.title?.removeFromSuperview()

        let title: UIVisualEffectView
        switch style {
        case .Light:
            title = UIVisualEffectView(effect: UIBlurEffect(style: .ExtraLight))

            self.titleText.textColor = LightTabCellUX.TabTitleTextColor
            self.titleText.backgroundColor = UIColor.clearColor()
        case .Dark:
            title = UIVisualEffectView(effect: UIBlurEffect(style: .Dark))

            self.titleText.textColor = DarkTabCellUX.TabTitleTextColor
            self.titleText.backgroundColor = UIColor.clearColor()
        }

        title.layer.shadowColor = UIColor.blackColor().CGColor
        title.layer.shadowOpacity = 0.2
        title.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        title.layer.shadowRadius = 0

        title.addSubview(self.closeButton)
        title.addSubview(self.titleText)
        title.addSubview(self.favicon)

        backgroundHolder.addSubview(title)
        self.title = title
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let w = frame.width
        let h = frame.height
        backgroundHolder.frame = CGRect(x: margin,
            y: margin,
            width: w,
            height: h)
        background.frame = CGRect(origin: CGPointMake(0, 0), size: backgroundHolder.frame.size)

        title.frame = CGRect(x: 0,
            y: 0,
            width: backgroundHolder.frame.width,
            height: TabTrayControllerUX.TextBoxHeight)

        favicon.frame = CGRect(x: 6,
            y: (TabTrayControllerUX.TextBoxHeight - TabTrayControllerUX.FaviconSize)/2,
            width: TabTrayControllerUX.FaviconSize,
            height: TabTrayControllerUX.FaviconSize)

        let titleTextLeft = favicon.frame.origin.x + favicon.frame.width + 6
        titleText.frame = CGRect(x: titleTextLeft,
            y: 0,
            width: title.frame.width - titleTextLeft - margin  - TabTrayControllerUX.CloseButtonSize - TabTrayControllerUX.CloseButtonMargin * 2,
            height: title.frame.height)

        innerStroke.frame = background.frame

        closeButton.snp_makeConstraints { make in
            make.size.equalTo(title.snp_height)
            make.trailing.centerY.equalTo(title)
        }

        let top = (TabTrayControllerUX.TextBoxHeight - titleText.bounds.height) / 2.0
        titleText.frame.origin = CGPoint(x: titleText.frame.origin.x, y: max(0, top))
    }


    override func prepareForReuse() {
        // Reset any close animations.
        backgroundHolder.transform = CGAffineTransformIdentity
        backgroundHolder.alpha = 1
    }

    override func accessibilityScroll(direction: UIAccessibilityScrollDirection) -> Bool {
        var right: Bool
        switch direction {
        case .Left:
            right = false
        case .Right:
            right = true
        default:
            return false
        }
        animator.close(right: right)
        return true
    }
}

class TabTrayController: UIViewController {
    let tabManager: TabManager
    let profile: Profile

    var collectionView: UICollectionView!
    var navBar: UIView!
    var addTabButton: UIButton!
    var settingsButton: UIButton!
    var collectionViewTransitionSnapshot: UIView?

    private var privateMode: Bool = false {
        didSet {
            if #available(iOS 9, *) {
                togglePrivateMode.selected = privateMode
                emptyPrivateTabsView.hidden = !(privateMode && tabManager.privateTabs.count == 0)
                tabDataSource.tabs = tabsToDisplay
                collectionView.reloadData()
            }
        }
    }

    private var tabsToDisplay: [Browser] {
        return self.privateMode ? tabManager.privateTabs : tabManager.normalTabs
    }

    @available(iOS 9, *)
    lazy var togglePrivateMode: UIButton = {
        let button = UIButton()
        button.setImage(UIImage(named: "smallPrivateMask"), forState: UIControlState.Normal)
        button.setImage(UIImage(named: "smallPrivateMaskSelected"), forState: UIControlState.Selected)
        button.addTarget(self, action: "SELdidTogglePrivateMode", forControlEvents: .TouchUpInside)
        button.accessibilityLabel = NSLocalizedString("Toggle Private Mode", comment: "Accessibility label for toggling on/off private mode")
        return button
    }()

    @available(iOS 9, *)
    private lazy var emptyPrivateTabsView: EmptyPrivateTabsView = {
        return EmptyPrivateTabsView()
    }()

    private lazy var tabDataSource: TabManagerDataSource = {
        return TabManagerDataSource(tabs: self.tabsToDisplay, cellDelegate: self)
    }()

    private lazy var tabLayoutDelegate: TabLayoutDelegate = {
        let delegate = TabLayoutDelegate(profile: self.profile, traitCollection: self.traitCollection)
        delegate.tabSelectionDelegate = self
        return delegate
    }()

    private var removedTabIndexPath: NSIndexPath?

    init(tabManager: TabManager, profile: Profile) {
        self.tabManager = tabManager
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

// MARK: View Controller Callbacks
    override func viewDidLoad() {
        super.viewDidLoad()

        view.accessibilityLabel = NSLocalizedString("Tabs Tray", comment: "Accessibility label for the Tabs Tray view.")
        tabManager.addDelegate(self)

        navBar = UIView()
        navBar.backgroundColor = TabTrayControllerUX.BackgroundColor

        let signInButton = UIButton(type: UIButtonType.Custom)
        signInButton.addTarget(self, action: "SELdidClickDone", forControlEvents: UIControlEvents.TouchUpInside)
        signInButton.setTitle(NSLocalizedString("Sign in", comment: "Button that leads to Sign in section of the Settings sheet."), forState: UIControlState.Normal)
        signInButton.setTitleColor(UIColor.whiteColor(), forState: UIControlState.Normal)
        // workaround for VoiceOver bug - if we create the button with UIButton.buttonWithType,
        // it gets initial frame with height 0 and accessibility somehow does not update the height
        // later and thus the button becomes completely unavailable to VoiceOver unless we
        // explicitly set the height to some (reasonable) non-zero value.
        // Also note that setting accessibilityFrame instead of frame has no effect.
        signInButton.frame.size.height = signInButton.intrinsicContentSize().height
        
        let navItem = UINavigationItem()
        navItem.titleView = signInButton
        signInButton.hidden = true //hiding sign in button until we decide on UX

        addTabButton = UIButton()
        addTabButton.setImage(UIImage(named: "add"), forState: .Normal)
        addTabButton.addTarget(self, action: "SELdidClickAddTab", forControlEvents: .TouchUpInside)
        addTabButton.accessibilityLabel = NSLocalizedString("Add Tab", comment: "Accessibility label for the Add Tab button in the Tab Tray.")

        settingsButton = UIButton()
        settingsButton.setImage(UIImage(named: "settings"), forState: .Normal)
        settingsButton.addTarget(self, action: "SELdidClickSettingsItem", forControlEvents: .TouchUpInside)
        settingsButton.accessibilityLabel = NSLocalizedString("Settings", comment: "Accessibility label for the Settings button in the Tab Tray.")

        let flowLayout = TabTrayCollectionViewLayout()
        collectionView = UICollectionView(frame: view.frame, collectionViewLayout: flowLayout)

        collectionView.dataSource = tabDataSource
        collectionView.delegate = tabLayoutDelegate

        collectionView.registerClass(TabCell.self, forCellWithReuseIdentifier: TabCell.Identifier)
        collectionView.backgroundColor = TabTrayControllerUX.BackgroundColor

        view.addSubview(collectionView)
        view.addSubview(navBar)
        view.addSubview(addTabButton)
        view.addSubview(settingsButton)

        makeConstraints()

        if #available(iOS 9, *) {
            view.addSubview(togglePrivateMode)
            togglePrivateMode.snp_makeConstraints { make in
                make.right.equalTo(addTabButton.snp_left).offset(-10)
                make.size.equalTo(UIConstants.ToolbarHeight)
                make.centerY.equalTo(self.navBar)
            }

            view.addSubview(emptyPrivateTabsView)
            emptyPrivateTabsView.hidden = !(privateMode && tabManager.privateTabs.count == 0)
            emptyPrivateTabsView.snp_makeConstraints { make in
                make.top.equalTo(navBar.snp_bottom)
                make.left.right.bottom.equalTo(self.view)
            }

            if let tab = tabManager.selectedTab where tab.isPrivate {
                privateMode = true
            }
        }
    }

    override func traitCollectionDidChange(previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // Update the trait collection we reference in our layout delegate
        tabLayoutDelegate.traitCollection = traitCollection
        collectionView.collectionViewLayout.invalidateLayout()
    }

    override func preferredStatusBarStyle() -> UIStatusBarStyle {
        return UIStatusBarStyle.LightContent
    }

    private func makeConstraints() {
        let viewBindings: [String: AnyObject] = [
            "topLayoutGuide" : topLayoutGuide,
            "navBar" : navBar
        ]

        let topConstraints = NSLayoutConstraint.constraintsWithVisualFormat("V:|[topLayoutGuide][navBar]", options: [], metrics: nil, views: viewBindings)
        view.addConstraints(topConstraints)

        navBar.snp_makeConstraints { make in
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.left.right.equalTo(self.view)
        }

        addTabButton.snp_makeConstraints { make in
            make.trailing.bottom.equalTo(self.navBar)
            make.size.equalTo(UIConstants.ToolbarHeight)
        }

        settingsButton.snp_makeConstraints { make in
            make.leading.bottom.equalTo(self.navBar)
            make.size.equalTo(UIConstants.ToolbarHeight)
        }

        collectionView.snp_makeConstraints { make in
            make.top.equalTo(navBar.snp_bottom)
            make.left.right.bottom.equalTo(self.view)
        }
    }

// MARK: Selectors
    func SELdidClickDone() {
        presentingViewController!.dismissViewControllerAnimated(true, completion: nil)
    }

    func SELdidClickSettingsItem() {
        let settingsTableViewController = SettingsTableViewController()
        settingsTableViewController.profile = profile
        settingsTableViewController.tabManager = tabManager

        let controller = SettingsNavigationController(rootViewController: settingsTableViewController)
        controller.popoverDelegate = self
		controller.modalPresentationStyle = UIModalPresentationStyle.FormSheet
        presentViewController(controller, animated: true, completion: nil)
    }

    func SELdidClickAddTab() {
        if #available(iOS 9, *) {
            if privateMode {
                emptyPrivateTabsView.hidden = true
            }
        }

        // We're only doing one update here, but using a batch update lets us delay selecting the tab
        // until after its insert animation finishes.
        self.collectionView.performBatchUpdates({ _ in
            var tab: Browser
            if #available(iOS 9, *) {
                tab = self.tabManager.addTab(isPrivate: self.privateMode)
            } else {
                tab = self.tabManager.addTab()
            }
            self.tabManager.selectTab(tab)
        }, completion: { finished in
            if finished {
                self.navigationController?.popViewControllerAnimated(true)
            }
        })
    }

    @available(iOS 9, *)
    func SELdidTogglePrivateMode() {
        privateMode = !privateMode
    }
}

extension TabTrayController: TabSelectionDelegate {
    func didSelectTabAtIndex(index: Int) {
        let tab = tabsToDisplay[index]
        tabManager.selectTab(tab)
        self.navigationController?.popViewControllerAnimated(true)
    }
}

extension TabTrayController: PresentingModalViewControllerDelegate {
    func dismissPresentedModalViewController(modalViewController: UIViewController, animated: Bool) {
        dismissViewControllerAnimated(animated, completion: { self.collectionView.reloadData() })
    }
}

extension TabTrayController: TabManagerDelegate {
    func tabManager(tabManager: TabManager, didSelectedTabChange selected: Browser?, previous: Browser?) {
    }

    func tabManager(tabManager: TabManager, didCreateTab tab: Browser, restoring: Bool) {
    }

    func tabManager(tabManager: TabManager, didAddTab tab: Browser, restoring: Bool) {
        // Get the index of the added tab from it's set (private or normal)
        guard let index = tabManager.indexForTab(tab, inTabs: tabsToDisplay) else { return }
        tabDataSource.tabs.append(tab)

        self.collectionView.performBatchUpdates({ _ in
            self.collectionView.insertItemsAtIndexPaths([NSIndexPath(forItem: index, inSection: 0)])
        }, completion: { finished in
            if finished {
                tabManager.selectTab(tab)
                // don't pop the tab tray view controller if it is not in the foreground
                if self.presentedViewController == nil {
                    self.navigationController?.popViewControllerAnimated(true)
                }
            }
        })
    }

    func tabManager(tabManager: TabManager, didRemoveTab tab: Browser) {
        if let removedIndex = removedTabIndexPath {
            tabDataSource.tabs.removeAtIndex(removedIndex.item)
            self.collectionView.deleteItemsAtIndexPaths([removedIndex])
            self.collectionView.reloadItemsAtIndexPaths(self.collectionView.indexPathsForVisibleItems())
            removedTabIndexPath = nil

            if #available(iOS 9, *) {
                if privateMode && tabsToDisplay.count == 0 {
                    emptyPrivateTabsView.hidden = false
                }
            }
        }
    }

    func tabManagerDidAddTabs(tabManager: TabManager) {
    }

    func tabManagerDidRestoreTabs(tabManager: TabManager) {
    }
}

extension TabTrayController: UIScrollViewAccessibilityDelegate {
    func accessibilityScrollStatusForScrollView(scrollView: UIScrollView) -> String? {
        var visibleCells = collectionView.visibleCells() as! [TabCell]
        var bounds = collectionView.bounds
        bounds = CGRectOffset(bounds, collectionView.contentInset.left, collectionView.contentInset.top)
        bounds.size.width -= collectionView.contentInset.left + collectionView.contentInset.right
        bounds.size.height -= collectionView.contentInset.top + collectionView.contentInset.bottom
        // visible cells do sometimes return also not visible cells when attempting to go past the last cell with VoiceOver right-flick gesture; so make sure we have only visible cells (yeah...)
        visibleCells = visibleCells.filter { !CGRectIsEmpty(CGRectIntersection($0.frame, bounds)) }

        var indexPaths = visibleCells.map { self.collectionView.indexPathForCell($0)! }
        indexPaths.sortInPlace { $0.section < $1.section || ($0.section == $1.section && $0.row < $1.row) }

        if indexPaths.count == 0 {
            return NSLocalizedString("No tabs", comment: "Message spoken by VoiceOver to indicate that there are no tabs in the Tabs Tray")
        }

        let firstTab = indexPaths.first!.row + 1
        let lastTab = indexPaths.last!.row + 1
        let tabCount = collectionView.numberOfItemsInSection(0)

        if (firstTab == lastTab) {
            let format = NSLocalizedString("Tab %@ of %@", comment: "Message spoken by VoiceOver saying the position of the single currently visible tab in Tabs Tray, along with the total number of tabs. E.g. \"Tab 2 of 5\" says that tab 2 is visible (and is the only visible tab), out of 5 tabs total.")
            return String(format: format, NSNumber(integer: firstTab), NSNumber(integer: tabCount))
        } else {
            let format = NSLocalizedString("Tabs %@ to %@ of %@", comment: "Message spoken by VoiceOver saying the range of tabs that are currently visible in Tabs Tray, along with the total number of tabs. E.g. \"Tabs 8 to 10 of 15\" says tabs 8, 9 and 10 are visible, out of 15 tabs total.")
            return String(format: format, NSNumber(integer: firstTab), NSNumber(integer: lastTab), NSNumber(integer: tabCount))
        }
    }
}

extension TabTrayController: SwipeAnimatorDelegate {
    func swipeAnimator(animator: SwipeAnimator, viewDidExitContainerBounds: UIView) {
        let tabCell = animator.container as! TabCell
        if let indexPath = collectionView.indexPathForCell(tabCell) {
            let tab = tabsToDisplay[indexPath.item]
            removedTabIndexPath = indexPath
            tabManager.removeTab(tab)
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NSLocalizedString("Closing tab", comment: ""))
        }
    }
}

extension TabTrayController: TabCellDelegate {
    func tabCellDidClose(cell: TabCell) {
        let indexPath = collectionView.indexPathForCell(cell)!
        let tab = tabsToDisplay[indexPath.item]
        removedTabIndexPath = indexPath
        tabManager.removeTab(tab)
    }
}

private class TabManagerDataSource: NSObject, UICollectionViewDataSource {
    unowned var cellDelegate: protocol<TabCellDelegate, SwipeAnimatorDelegate>
    var tabs: [Browser]

    init(tabs: [Browser], cellDelegate: protocol<TabCellDelegate, SwipeAnimatorDelegate>) {
        self.cellDelegate = cellDelegate
        self.tabs = tabs
        super.init()
    }

    @objc func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let tabCell = collectionView.dequeueReusableCellWithReuseIdentifier(TabCell.Identifier, forIndexPath: indexPath) as! TabCell
        tabCell.animator.delegate = cellDelegate
        tabCell.delegate = cellDelegate

        let tab = tabs[indexPath.item]
        tabCell.style = tab.isPrivate ? .Dark : .Light
        tabCell.titleText.text = tab.displayTitle

        if !tab.displayTitle.isEmpty {
            tabCell.accessibilityLabel = tab.displayTitle
        } else {
            tabCell.accessibilityLabel = AboutUtils.getAboutComponent(tab.url)
        }

        tabCell.isAccessibilityElement = true
        tabCell.accessibilityHint = NSLocalizedString("Swipe right or left with three fingers to close the tab.", comment: "Accessibility hint for tab tray's displayed tab.")

        if let favIcon = tab.displayFavicon {
            tabCell.favicon.sd_setImageWithURL(NSURL(string: favIcon.url)!)
        } else {
            tabCell.favicon.image = UIImage(named: "defaultFavicon")
        }

        tabCell.background.image = tab.screenshot
        return tabCell
    }

    @objc func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tabs.count
    }
}

@objc protocol TabSelectionDelegate: class {
    func didSelectTabAtIndex(index :Int)
}

private class TabLayoutDelegate: NSObject, UICollectionViewDelegateFlowLayout {
    weak var tabSelectionDelegate: TabSelectionDelegate?

    private var traitCollection: UITraitCollection
    private var profile: Profile
    private var numberOfColumns: Int {
        let compactLayout = profile.prefs.boolForKey("CompactTabLayout") ?? true

        // iPhone 4-6+ portrait
        if traitCollection.horizontalSizeClass == .Compact && traitCollection.verticalSizeClass == .Regular {
            return compactLayout ? TabTrayControllerUX.CompactNumberOfColumnsThin : TabTrayControllerUX.NumberOfColumnsThin
        } else {
            return TabTrayControllerUX.NumberOfColumnsWide
        }
    }

    init(profile: Profile, traitCollection: UITraitCollection) {
        self.profile = profile
        self.traitCollection = traitCollection
        super.init()
    }

    private func cellHeightForCurrentDevice() -> CGFloat {
        let compactLayout = profile.prefs.boolForKey("CompactTabLayout") ?? true
        let shortHeight = (compactLayout ? TabTrayControllerUX.TextBoxHeight * 6 : TabTrayControllerUX.TextBoxHeight * 5)

        if self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClass.Compact {
            return shortHeight
        } else if self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClass.Compact {
            return shortHeight
        } else {
            return TabTrayControllerUX.TextBoxHeight * 8
        }
    }

    @objc func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAtIndex section: Int) -> CGFloat {
        return TabTrayControllerUX.Margin
    }

    @objc func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        let cellWidth = (collectionView.bounds.width - TabTrayControllerUX.Margin * CGFloat(numberOfColumns + 1)) / CGFloat(numberOfColumns)
        return CGSizeMake(cellWidth, self.cellHeightForCurrentDevice())
    }

    @objc func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAtIndex section: Int) -> UIEdgeInsets {
        return UIEdgeInsetsMake(TabTrayControllerUX.Margin, TabTrayControllerUX.Margin, TabTrayControllerUX.Margin, TabTrayControllerUX.Margin)
    }

    @objc func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAtIndex section: Int) -> CGFloat {
        return TabTrayControllerUX.Margin
    }

    @objc func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        tabSelectionDelegate?.didSelectTabAtIndex(indexPath.row)
    }
}

// There seems to be a bug with UIKit where when the UICollectionView changes its contentSize
// from > frame.size to <= frame.size: the contentSet animation doesn't properly happen and 'jumps' to the
// final state.
// This workaround forces the contentSize to always be larger than the frame size so the animation happens more
// smoothly. This also makes the tabs be able to 'bounce' when there are not enough to fill the screen, which I
// think is fine, but if needed we can disable user scrolling in this case.
private class TabTrayCollectionViewLayout: UICollectionViewFlowLayout {
    private override func collectionViewContentSize() -> CGSize {
        var calculatedSize = super.collectionViewContentSize()
        let collectionViewHeight = collectionView?.bounds.size.height ?? 0
        if calculatedSize.height < collectionViewHeight && collectionViewHeight > 0 {
            calculatedSize.height = collectionViewHeight + 1
        }
        return calculatedSize
    }
}

// A transparent view with a rectangular border with rounded corners, stroked
// with a semi-transparent white border.
class InnerStrokedView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor.clearColor()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawRect(rect: CGRect) {
        let strokeWidth = 1.0 as CGFloat
        let halfWidth = strokeWidth/2 as CGFloat

        let path = UIBezierPath(roundedRect: CGRect(x: halfWidth,
            y: halfWidth,
            width: rect.width - strokeWidth,
            height: rect.height - strokeWidth),
            cornerRadius: TabTrayControllerUX.CornerRadius)
        
        path.lineWidth = strokeWidth
        UIColor.whiteColor().colorWithAlphaComponent(0.2).setStroke()
        path.stroke()
    }
}

struct EmptyPrivateTabsViewUX {
    static let TitleColor = UIColor.whiteColor()
    static let TitleFont = UIFont.systemFontOfSize(22, weight: UIFontWeightMedium)
    static let DescriptionColor = UIColor.whiteColor()
    static let DescriptionFont = UIFont.systemFontOfSize(17)
    static let TextMargin: CGFloat = 18
    static let MaxDescriptionWidth: CGFloat = 250
}

// View we display when there are no private tabs created
private class EmptyPrivateTabsView: UIView {
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = EmptyPrivateTabsViewUX.TitleColor
        label.font = EmptyPrivateTabsViewUX.TitleFont
        label.textAlignment = NSTextAlignment.Center
        return label
    }()

    private var descriptionLabel: UILabel = {
        let label = UILabel()
        label.textColor = EmptyPrivateTabsViewUX.DescriptionColor
        label.font = EmptyPrivateTabsViewUX.DescriptionFont
        label.textAlignment = NSTextAlignment.Center
        label.numberOfLines = 3
        label.preferredMaxLayoutWidth = EmptyPrivateTabsViewUX.MaxDescriptionWidth
        return label
    }()

    private var iconImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "largePrivateMask"))
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.text =  NSLocalizedString("Private Browsing",
            tableName: "PrivateBrowsing", comment: "Title displayed for when there are no open tabs while in private mode")
        descriptionLabel.text = NSLocalizedString("Firefox won't remember any of your history or cookies, but new bookmarks will be saved.",
            tableName: "PrivateBrowsing", comment: "Description text displayed when there are no open tabs while in private mode")

        addSubview(titleLabel)
        addSubview(descriptionLabel)
        addSubview(iconImageView)

        titleLabel.snp_makeConstraints { make in
            make.center.equalTo(self)
        }

        iconImageView.snp_makeConstraints { make in
            make.bottom.equalTo(titleLabel.snp_top).offset(-EmptyPrivateTabsViewUX.TextMargin)
            make.centerX.equalTo(self)
        }

        descriptionLabel.snp_makeConstraints { make in
            make.top.equalTo(titleLabel.snp_bottom).offset(EmptyPrivateTabsViewUX.TextMargin)
            make.centerX.equalTo(self)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
