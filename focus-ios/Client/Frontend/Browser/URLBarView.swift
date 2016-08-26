/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import Shared
import SnapKit
import XCGLogger

private let log = Logger.browserLogger

struct URLBarViewUX {
    static let TextFieldBorderColor = UIColor(rgb: 0xBBBBBB)
    static let TextFieldActiveBorderColor = UIColor(rgb: 0x4A90E2)
    static let TextFieldContentInset = UIOffsetMake(9, 5)
    static let LocationLeftPadding: CGFloat = 5
    static let LocationHeight: CGFloat = 28
    static let LocationContentOffset: CGFloat = 8
    static let TextFieldCornerRadius: CGFloat = 3
    static let TextFieldBorderWidth: CGFloat = 1
    // offset from edge of tabs button
    static let URLBarCurveOffset: CGFloat = 14
    static let URLBarCurveOffsetLeft: CGFloat = -10
    // buffer so we dont see edges when animation overshoots with spring
    static let URLBarCurveBounceBuffer: CGFloat = 8
    static let ProgressTintColor = UIColor(red:1, green:0.32, blue:0, alpha:1)

    static let MinifiedURLBarHeight: CGFloat = 26

    static let TabsButtonRotationOffset: CGFloat = 1.5
    static let TabsButtonHeight: CGFloat = 18.0
    static let ToolbarButtonInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

    static let Themes: [String: Theme] = {
        var themes = [String: Theme]()
        var theme = Theme()
        theme.borderColor = UIConstants.PrivateModeLocationBorderColor
        theme.activeBorderColor = UIConstants.PrivateModePurple
        theme.tintColor = UIConstants.PrivateModePurple
        theme.textColor = UIColor.whiteColor()
        theme.buttonTintColor = UIConstants.PrivateModeActionButtonTintColor
        themes[Theme.PrivateMode] = theme

        theme = Theme()
        theme.borderColor = TextFieldBorderColor
        theme.activeBorderColor = TextFieldActiveBorderColor
        theme.tintColor = ProgressTintColor
        theme.textColor = UIColor.blackColor()
        theme.buttonTintColor = UIColor.darkGrayColor()
        themes[Theme.NormalMode] = theme

        return themes
    }()

    static func backgroundColorWithAlpha(alpha: CGFloat) -> UIColor {
        return UIConstants.AppBackgroundColor.colorWithAlphaComponent(alpha)
    }
}

protocol URLBarDelegate: class {
    func urlBarDidPressTabs(urlBar: URLBarView)
    func urlBarDidPressReaderMode(urlBar: URLBarView)
    /// - returns: whether the long-press was handled by the delegate; i.e. return `false` when the conditions for even starting handling long-press were not satisfied
    func urlBarDidLongPressReaderMode(urlBar: URLBarView) -> Bool
    func urlBarDidPressStop(urlBar: URLBarView)
    func urlBarDidPressReload(urlBar: URLBarView)
    func urlBarDidEnterOverlayMode(urlBar: URLBarView)
    func urlBarDidLeaveOverlayMode(urlBar: URLBarView)
    func urlBarDidLongPressLocation(urlBar: URLBarView)
    func urlBarLocationAccessibilityActions(urlBar: URLBarView) -> [UIAccessibilityCustomAction]?
    func urlBar(urlBar: URLBarView, didEnterText text: String)
    func urlBar(urlBar: URLBarView, didSubmitText text: String)
    func urlBarDisplayTextForURL(url: NSURL?) -> String?
}

class URLBarView: UIView {
    // Additional UIAppearance-configurable properties
    dynamic var locationBorderColor: UIColor = URLBarViewUX.TextFieldBorderColor {
        didSet {
            if !inOverlayMode {
                locationContainer.layer.borderColor = locationBorderColor.CGColor
            }
        }
    }
    dynamic var locationActiveBorderColor: UIColor = URLBarViewUX.TextFieldActiveBorderColor {
        didSet {
            if inOverlayMode {
                locationContainer.layer.borderColor = locationActiveBorderColor.CGColor
            }
        }
    }

    // The transition between the URL bar being fully displayed (1.0) and being minimised (0.0)
    var transitionValue: CGFloat = 1.0 {
        didSet {
            let inverseState = 1.0 - transitionValue
            // Interaction
            self.locationContainer.userInteractionEnabled = transitionValue == 1.0

            // Spacing
            let offsetToHide = UIConstants.ToolbarHeight + URLBarViewUX.URLBarCurveOffset - URLBarViewUX.LocationLeftPadding
            let offsetForState = inverseState * offsetToHide
            if !self.topTabsIsShowing {
                self.tabsButton.snp_updateConstraints { make in
                    make.trailing.equalTo(offsetForState)
                }
            }
            self.curveShape.snp_updateConstraints { make in
                self.rightBarConstraint = make.right.equalTo(self.defaultRightOffset + offsetForState).constraint
            }
            self.locationContainer.snp_updateConstraints { make in
                let border = (UIConstants.ToolbarHeight - URLBarViewUX.LocationHeight) / 2
                let offset = (UIConstants.ToolbarHeight - URLBarViewUX.MinifiedURLBarHeight) / 2
                make.top.equalTo(border + offset * inverseState)
                make.bottom.equalTo(-border + offset * inverseState)
            }
            if let text = self.locationView.urlTextField.text, font = self.locationView.urlTextField.font {
                let urlTextWidth = min(NSString(string: text).boundingRectWithSize(self.locationView.urlTextField.bounds.size, options: .TruncatesLastVisibleLine, attributes: [NSFontAttributeName: font], context: nil).width, self.locationView.urlTextField.bounds.width)
                let maxOffset = self.bounds.width / 2 - self.locationView.convertPoint(CGPoint(x: urlTextWidth / 2 + self.locationView.urlTextLeading, y: 0), toView: self).x
                self.locationView.urlTextField.snp_updateConstraints { make in
                    make.leading.equalTo(self.locationView.urlTextLeading + inverseState * maxOffset)
                    make.trailing.equalTo(self.locationView.urlTextTrailing + inverseState * maxOffset)
                }
                self.locationView.lockImageView.snp_updateConstraints { make in
                    make.leading.equalTo(inverseState * maxOffset)
                }
            }

            // Transparency
            self.locationContainer.layer.borderColor = self.locationBorderColor.colorWithAlphaComponent(transitionValue * self.locationBorderColor.alpha).CGColor
            self.locationView.setBackgroundAlpha(transitionValue)
            if !self.inOverlayMode {
                self.actionButtons.forEach { $0.alpha = transitionValue }
            }
            self.border.alpha = inverseState
        }
    }

    weak var delegate: URLBarDelegate?
    weak var tabToolbarDelegate: TabToolbarDelegate?
    var helper: TabToolbarHelper?
    var isTransitioning: Bool = false {
        didSet {
            if isTransitioning {
                // Cancel any pending/in-progress animations related to the progress bar
                self.progressBar.setProgress(1, animated: false)
                self.progressBar.alpha = 0.0
            }
        }
    }

    private var currentTheme: String = Theme.NormalMode

    var toolbarIsShowing = false
    var topTabsIsShowing = false {
        didSet {
            curveShape.hidden = topTabsIsShowing
        }
    }

    private var locationTextField: ToolbarTextField?

    /// Overlay mode is the state where the lock/reader icons are hidden, the home panels are shown,
    /// and the Cancel button is visible (allowing the user to leave overlay mode). Overlay mode
    /// is *not* tied to the location text field's editing state; for instance, when selecting
    /// a panel, the first responder will be resigned, yet the overlay mode UI is still active.
    var inOverlayMode = false

    lazy var locationView: TabLocationView = {
        let locationView = TabLocationView()
        locationView.translatesAutoresizingMaskIntoConstraints = false
        locationView.layer.cornerRadius = URLBarViewUX.TextFieldCornerRadius
        locationView.readerModeState = ReaderModeState.Unavailable
        locationView.delegate = self
        return locationView
    }()

    lazy var locationContainer: UIView = {
        let locationContainer = UIView()
        locationContainer.translatesAutoresizingMaskIntoConstraints = false

        locationContainer.layer.borderColor = self.locationBorderColor.CGColor
        locationContainer.layer.cornerRadius = URLBarViewUX.TextFieldCornerRadius
        locationContainer.layer.borderWidth = URLBarViewUX.TextFieldBorderWidth

        return locationContainer
    }()

    private lazy var tabsButton: TabsButton = {
        let tabsButton = TabsButton.tabTrayButton()
        tabsButton.addTarget(self, action: #selector(URLBarView.SELdidClickAddTab), forControlEvents: UIControlEvents.TouchUpInside)
        tabsButton.accessibilityIdentifier = "URLBarView.tabsButton"
        return tabsButton
    }()

    private lazy var progressBar: UIProgressView = {
        let progressBar = UIProgressView()
        progressBar.progressTintColor = URLBarViewUX.ProgressTintColor
        progressBar.alpha = 0
        progressBar.hidden = true
        return progressBar
    }()

    private lazy var cancelButton: UIButton = {
        let cancelButton = InsetButton()
        cancelButton.setTitleColor(UIColor.blackColor(), forState: UIControlState.Normal)
        let cancelTitle = NSLocalizedString("Cancel", comment: "Label for Cancel button")
        cancelButton.setTitle(cancelTitle, forState: UIControlState.Normal)
        cancelButton.titleLabel?.font = UIConstants.DefaultChromeFont
        cancelButton.addTarget(self, action: #selector(URLBarView.SELdidClickCancel), forControlEvents: UIControlEvents.TouchUpInside)
        cancelButton.titleEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12)
        cancelButton.setContentHuggingPriority(1000, forAxis: UILayoutConstraintAxis.Horizontal)
        cancelButton.setContentCompressionResistancePriority(1000, forAxis: UILayoutConstraintAxis.Horizontal)
        cancelButton.alpha = 0
        return cancelButton
    }()
    
    private lazy var border: UIView = {
        let border = UIView()
        border.backgroundColor = UIConstants.BorderColor
        border.alpha = 0
        return border
    }()

    private lazy var curveShape: CurveView = { return CurveView() }()

    lazy var shareButton: UIButton = { return UIButton() }()

    lazy var menuButton: UIButton = { return UIButton() }()

    lazy var bookmarkButton: UIButton = { return UIButton() }()

    lazy var forwardButton: UIButton = { return UIButton() }()

    lazy var backButton: UIButton = { return UIButton() }()

    lazy var stopReloadButton: UIButton = { return UIButton() }()

    lazy var homePageButton: UIButton = { return UIButton() }()

    lazy var actionButtons: [UIButton] = {
        return AppConstants.MOZ_MENU ? [self.shareButton, self.menuButton, self.forwardButton, self.backButton, self.stopReloadButton, self.homePageButton] : [self.shareButton, self.bookmarkButton, self.forwardButton, self.backButton, self.stopReloadButton]
    }()

    private var rightBarConstraint: Constraint?
    private let defaultRightOffset: CGFloat = URLBarViewUX.URLBarCurveOffset - URLBarViewUX.URLBarCurveBounceBuffer

    var currentURL: NSURL? {
        get {
            return locationView.url
        }

        set(newURL) {
            locationView.url = newURL
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = URLBarViewUX.backgroundColorWithAlpha(0)
        addSubview(curveShape)
        addSubview(border)

        addSubview(progressBar)
        addSubview(tabsButton)
        addSubview(cancelButton)

        addSubview(shareButton)
        if AppConstants.MOZ_MENU {
            addSubview(menuButton)
            addSubview(homePageButton)
        } else {
            addSubview(bookmarkButton)
        }
        addSubview(forwardButton)
        addSubview(backButton)
        addSubview(stopReloadButton)

        locationContainer.addSubview(locationView)
        addSubview(locationContainer)

        helper = TabToolbarHelper(toolbar: self)
        setupConstraints()

        // Make sure we hide any views that shouldn't be showing in non-overlay mode.
        updateViewsForOverlayModeAndToolbarChanges()
    }

    private func setupConstraints() {

        progressBar.snp_makeConstraints { make in
            make.top.equalTo(self.snp_bottom)
            make.width.equalTo(self)
        }

        border.snp_makeConstraints { make in
            make.bottom.left.right.equalTo(self)
            make.height.equalTo(0.5)
        }

        locationView.snp_makeConstraints { make in
            make.edges.equalTo(self.locationContainer)
        }

        cancelButton.snp_makeConstraints { make in
            make.centerY.equalTo(self.locationContainer)
            make.trailing.equalTo(self)
        }

        tabsButton.snp_makeConstraints { make in
            make.centerY.equalTo(self)
            make.trailing.equalTo(self)
            make.size.equalTo(UIConstants.ToolbarHeight)
        }

        curveShape.snp_makeConstraints { make in
            make.top.left.bottom.equalTo(self)
            self.rightBarConstraint = make.right.equalTo(self).constraint
            self.rightBarConstraint?.updateOffset(defaultRightOffset)
        }

        backButton.snp_makeConstraints { make in
            make.left.centerY.equalTo(self)
            make.size.equalTo(UIConstants.ToolbarHeight)
        }

        forwardButton.snp_makeConstraints { make in
            make.left.equalTo(self.backButton.snp_right)
            make.centerY.equalTo(self)
            make.size.equalTo(backButton)
        }

        stopReloadButton.snp_makeConstraints { make in
            make.left.equalTo(self.forwardButton.snp_right)
            make.centerY.equalTo(self)
            make.size.equalTo(backButton)
        }

        if AppConstants.MOZ_MENU {
            shareButton.snp_makeConstraints { make in
                make.right.equalTo(self.menuButton.snp_left)
                make.centerY.equalTo(self)
                make.size.equalTo(backButton)
            }

            homePageButton.snp_makeConstraints { make in
                make.center.equalTo(shareButton)
                make.size.equalTo(shareButton)
            }

            menuButton.snp_makeConstraints { make in
                make.right.equalTo(self.tabsButton.snp_left).offset(URLBarViewUX.URLBarCurveOffsetLeft)
                make.centerY.equalTo(self)
                make.size.equalTo(backButton)
            }
        } else {
            shareButton.snp_makeConstraints { make in
                make.right.equalTo(self.bookmarkButton.snp_left)
                make.centerY.equalTo(self)
                make.size.equalTo(backButton)
            }

            bookmarkButton.snp_makeConstraints { make in
                make.right.equalTo(self.tabsButton.snp_left).offset(URLBarViewUX.URLBarCurveOffsetLeft)
                make.centerY.equalTo(self)
                make.size.equalTo(backButton)
            }
        }
    }

    override func updateConstraints() {
        super.updateConstraints()
        if inOverlayMode {
            // In overlay mode, we always show the location view full width
            self.locationContainer.snp_remakeConstraints { make in
                make.leading.equalTo(self).offset(URLBarViewUX.LocationLeftPadding)
                make.trailing.equalTo(self.cancelButton.snp_leading)
                make.height.equalTo(URLBarViewUX.LocationHeight)
                make.centerY.equalTo(self)
            }
        } else {
            if topTabsIsShowing {
                tabsButton.snp_remakeConstraints { make in
                    make.centerY.equalTo(self.locationContainer)
                    make.leading.equalTo(self.snp_trailing)
                    make.size.equalTo(UIConstants.ToolbarHeight)
                }
            } else {
                tabsButton.snp_remakeConstraints { make in
                    if self.toolbarIsShowing {
                        make.centerY.equalTo(self)
                    } else {
                        make.centerY.equalTo(self.locationContainer)
                    }
                    make.trailing.equalTo(self)
                    make.size.equalTo(UIConstants.ToolbarHeight)
                }
            }
            self.locationContainer.snp_remakeConstraints { make in
                if self.toolbarIsShowing {
                    // If we are showing a toolbar, show the text field next to the forward button
                    make.leading.equalTo(self.stopReloadButton.snp_trailing)
                    make.trailing.equalTo(self.shareButton.snp_leading)
                } else {
                    // Otherwise, left align the location view
                    make.leading.equalTo(self).offset(URLBarViewUX.LocationLeftPadding)
                    make.trailing.equalTo(self.tabsButton.snp_leading).offset(-14)
                }
            }
        }
        // Fire the didSet handler to update the constraints regarding the minified URL bar
        self.transitionValue = (self.transitionValue)
    }

    func createLocationTextField() {
        guard locationTextField == nil else { return }

        locationTextField = ToolbarTextField()

        guard let locationTextField = locationTextField else { return }

        locationTextField.translatesAutoresizingMaskIntoConstraints = false
        locationTextField.layer.cornerRadius = URLBarViewUX.TextFieldCornerRadius
        locationTextField.autocompleteDelegate = self
        locationTextField.keyboardType = UIKeyboardType.WebSearch
        locationTextField.autocorrectionType = UITextAutocorrectionType.No
        locationTextField.autocapitalizationType = UITextAutocapitalizationType.None
        locationTextField.returnKeyType = UIReturnKeyType.Go
        locationTextField.clearButtonMode = UITextFieldViewMode.WhileEditing
        locationTextField.font = UIConstants.DefaultChromeFont
        locationTextField.accessibilityIdentifier = "address"
        locationTextField.accessibilityLabel = NSLocalizedString("Address and Search", comment: "Accessibility label for address and search field, both words (Address, Search) are therefore nouns.")
        locationTextField.attributedPlaceholder = self.locationView.placeholder

        locationContainer.addSubview(locationTextField)

        locationTextField.snp_makeConstraints { make in
            make.edges.equalTo(self.locationView.urlTextField)
        }

        locationTextField.applyTheme(currentTheme)
    }

    func removeLocationTextField() {
        locationTextField?.removeFromSuperview()
        locationTextField = nil
    }

    // Ideally we'd split this implementation in two, one URLBarView with a toolbar and one without
    // However, switching views dynamically at runtime is a difficult. For now, we just use one view
    // that can show in either mode.
    func setShowToolbar(shouldShow: Bool) {
        toolbarIsShowing = shouldShow
        setNeedsUpdateConstraints()
        // when we transition from portrait to landscape, calling this here causes
        // the constraints to be calculated too early and there are constraint errors
        if !toolbarIsShowing {
            updateConstraintsIfNeeded()
        }
        updateViewsForOverlayModeAndToolbarChanges()
    }

    func updateTabCount(count: Int, animated: Bool = true) {
        self.tabsButton.updateTabCount(count, animated: animated)
    }

    func updateProgressBar(progress: Float) {
        if progress == 1.0 {
            self.progressBar.setProgress(progress, animated: !isTransitioning)
            UIView.animateWithDuration(1.5, animations: {
                self.progressBar.alpha = 0.0
            })
        } else {
            if self.progressBar.alpha < 1.0 {
                self.progressBar.alpha = 1.0
            }
            self.progressBar.setProgress(progress, animated: (progress > progressBar.progress) && !isTransitioning)
        }
    }

    func updateReaderModeState(state: ReaderModeState) {
        locationView.readerModeState = state
    }

    func setAutocompleteSuggestion(suggestion: String?) {
        locationTextField?.setAutocompleteSuggestion(suggestion)
    }

    func enterOverlayMode(locationText: String?, pasted: Bool) {
        createLocationTextField()

        // Show the overlay mode UI, which includes hiding the locationView and replacing it
        // with the editable locationTextField.
        animateToOverlayState(overlayMode: true)

        delegate?.urlBarDidEnterOverlayMode(self)

        // Bug 1193755 Workaround - Calling becomeFirstResponder before the animation happens
        // won't take the initial frame of the label into consideration, which makes the label
        // look squished at the start of the animation and expand to be correct. As a workaround,
        // we becomeFirstResponder as the next event on UI thread, so the animation starts before we
        // set a first responder.
        if pasted {
            // Clear any existing text, focus the field, then set the actual pasted text.
            // This avoids highlighting all of the text.
            self.locationTextField?.text = ""
            dispatch_async(dispatch_get_main_queue()) {
                self.locationTextField?.becomeFirstResponder()
                self.locationTextField?.text = locationText
            }
        } else {
            // Copy the current URL to the editable text field, then activate it.
            self.locationTextField?.text = locationText
            dispatch_async(dispatch_get_main_queue()) {
                self.locationTextField?.becomeFirstResponder()
            }
        }
    }

    func leaveOverlayMode(didCancel cancel: Bool = false) {
        locationTextField?.resignFirstResponder()
        animateToOverlayState(overlayMode: false, didCancel: cancel)
        delegate?.urlBarDidLeaveOverlayMode(self)
    }

    func prepareOverlayAnimation() {
        // Make sure everything is showing during the transition (we'll hide it afterwards).
        self.bringSubviewToFront(self.locationContainer)
        self.cancelButton.hidden = false
        self.progressBar.hidden = false
        if AppConstants.MOZ_MENU {
            self.menuButton.hidden = !self.toolbarIsShowing
        } else {
            self.bookmarkButton.hidden = !self.toolbarIsShowing
        }
        self.forwardButton.hidden = !self.toolbarIsShowing
        self.backButton.hidden = !self.toolbarIsShowing
        self.stopReloadButton.hidden = !self.toolbarIsShowing
    }

    func transitionToOverlay(didCancel: Bool = false) {
        self.cancelButton.alpha = inOverlayMode ? 1 : 0
        self.progressBar.alpha = inOverlayMode || didCancel ? 0 : 1
        self.shareButton.alpha = inOverlayMode ? 0 : 1
        if AppConstants.MOZ_MENU {
            self.menuButton.alpha = inOverlayMode ? 0 : 1
        } else {
            self.bookmarkButton.alpha = inOverlayMode ? 0 : 1
        }
        self.forwardButton.alpha = inOverlayMode ? 0 : 1
        self.backButton.alpha = inOverlayMode ? 0 : 1
        self.stopReloadButton.alpha = inOverlayMode ? 0 : 1

        let borderColor = inOverlayMode ? locationActiveBorderColor : locationBorderColor
        locationContainer.layer.borderColor = borderColor.CGColor

        if inOverlayMode {
            self.cancelButton.transform = CGAffineTransformIdentity
            let tabsButtonTransform = CGAffineTransformMakeTranslation(self.tabsButton.frame.width + URLBarViewUX.URLBarCurveOffset, 0)
            self.tabsButton.transform = tabsButtonTransform
            self.rightBarConstraint?.updateOffset(URLBarViewUX.URLBarCurveOffset + URLBarViewUX.URLBarCurveBounceBuffer + tabsButton.frame.width)

            // Make the editable text field span the entire URL bar, covering the lock and reader icons.
            self.locationTextField?.snp_remakeConstraints { make in
                make.leading.equalTo(self.locationContainer).offset(URLBarViewUX.LocationContentOffset)
                make.top.bottom.trailing.equalTo(self.locationContainer)
            }
        } else {
            self.tabsButton.transform = CGAffineTransformIdentity
            self.cancelButton.transform = CGAffineTransformMakeTranslation(self.cancelButton.frame.width, 0)
            self.rightBarConstraint?.updateOffset(defaultRightOffset)

            // Shrink the editable text field back to the size of the location view before hiding it.
            self.locationTextField?.snp_remakeConstraints { make in
                make.edges.equalTo(self.locationView.urlTextField)
            }
        }
    }

    func updateViewsForOverlayModeAndToolbarChanges() {
        self.cancelButton.hidden = !inOverlayMode
        self.progressBar.hidden = inOverlayMode
        if AppConstants.MOZ_MENU {
            self.menuButton.hidden = !self.toolbarIsShowing || inOverlayMode
        } else {
            self.bookmarkButton.hidden = !self.toolbarIsShowing || inOverlayMode
        }
        self.forwardButton.hidden = !self.toolbarIsShowing || inOverlayMode
        self.backButton.hidden = !self.toolbarIsShowing || inOverlayMode
        self.stopReloadButton.hidden = !self.toolbarIsShowing || inOverlayMode
        self.tabsButton.hidden = self.topTabsIsShowing
    }

    func animateToOverlayState(overlayMode overlay: Bool, didCancel cancel: Bool = false) {
        prepareOverlayAnimation()
        layoutIfNeeded()

        inOverlayMode = overlay

        if !overlay {
            removeLocationTextField()
        }

        UIView.animateWithDuration(0.3, delay: 0.0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.0, options: [], animations: { _ in
            self.transitionToOverlay(cancel)
            self.setNeedsUpdateConstraints()
            self.layoutIfNeeded()
        }, completion: { _ in
            self.updateViewsForOverlayModeAndToolbarChanges()
        })
    }

    func SELdidClickAddTab() {
        delegate?.urlBarDidPressTabs(self)
    }

    func SELdidClickCancel() {
        leaveOverlayMode(didCancel: true)
    }
}

extension URLBarView: TabToolbarProtocol {
    func updateBackStatus(canGoBack: Bool) {
        backButton.enabled = canGoBack
    }

    func updateForwardStatus(canGoForward: Bool) {
        forwardButton.enabled = canGoForward
    }

    func updateBookmarkStatus(isBookmarked: Bool) {
        bookmarkButton.selected = isBookmarked
    }

    func updateReloadStatus(isLoading: Bool) {
        helper?.updateReloadStatus(isLoading)
        if isLoading {
            stopReloadButton.setImage(helper?.ImageStop, forState: .Normal)
            stopReloadButton.setImage(helper?.ImageStopPressed, forState: .Highlighted)
        } else {
            stopReloadButton.setImage(helper?.ImageReload, forState: .Normal)
            stopReloadButton.setImage(helper?.ImageReloadPressed, forState: .Highlighted)
        }
    }

    func updatePageStatus(isWebPage isWebPage: Bool) {
        if !AppConstants.MOZ_MENU {
            bookmarkButton.enabled = isWebPage
        }
        stopReloadButton.enabled = isWebPage
        shareButton.enabled = isWebPage
    }

    override var accessibilityElements: [AnyObject]? {
        get {
            if inOverlayMode {
                guard let locationTextField = locationTextField else { return nil }
                return [locationTextField, cancelButton]
            } else {
                if toolbarIsShowing {
                    return AppConstants.MOZ_MENU ? [backButton, forwardButton, stopReloadButton, locationView, shareButton, menuButton, tabsButton, progressBar] : [backButton, forwardButton, stopReloadButton, locationView, shareButton, bookmarkButton, tabsButton, progressBar]
                } else {
                    return [locationView, tabsButton, progressBar]
                }
            }
        }
        set {
            super.accessibilityElements = newValue
        }
    }
}

extension URLBarView: TabLocationViewDelegate {
    func tabLocationViewDidLongPressReaderMode(tabLocationView: TabLocationView) -> Bool {
        return delegate?.urlBarDidLongPressReaderMode(self) ?? false
    }

    func tabLocationViewDidTapLocation(tabLocationView: TabLocationView) {
        let locationText = delegate?.urlBarDisplayTextForURL(locationView.url)
        enterOverlayMode(locationText, pasted: false)
    }

    func tabLocationViewDidLongPressLocation(tabLocationView: TabLocationView) {
        delegate?.urlBarDidLongPressLocation(self)
    }

    func tabLocationViewDidTapReload(tabLocationView: TabLocationView) {
        delegate?.urlBarDidPressReload(self)
    }
    
    func tabLocationViewDidTapStop(tabLocationView: TabLocationView) {
        delegate?.urlBarDidPressStop(self)
    }

    func tabLocationViewDidTapReaderMode(tabLocationView: TabLocationView) {
        delegate?.urlBarDidPressReaderMode(self)
    }

    func tabLocationViewLocationAccessibilityActions(tabLocationView: TabLocationView) -> [UIAccessibilityCustomAction]? {
        return delegate?.urlBarLocationAccessibilityActions(self)
    }
}

extension URLBarView: AutocompleteTextFieldDelegate {
    func autocompleteTextFieldShouldReturn(autocompleteTextField: AutocompleteTextField) -> Bool {
        guard let text = locationTextField?.text else { return true }
        if !text.stringByTrimmingCharactersInSet(.whitespaceCharacterSet()).isEmpty {
            delegate?.urlBar(self, didSubmitText: text)
            return true
        } else {
            return false
        }
    }

    func autocompleteTextField(autocompleteTextField: AutocompleteTextField, didEnterText text: String) {
        delegate?.urlBar(self, didEnterText: text)
    }

    func autocompleteTextFieldDidBeginEditing(autocompleteTextField: AutocompleteTextField) {
        autocompleteTextField.highlightAll()
    }

    func autocompleteTextFieldShouldClear(autocompleteTextField: AutocompleteTextField) -> Bool {
        delegate?.urlBar(self, didEnterText: "")
        return true
    }
}

// MARK: UIAppearance
extension URLBarView {
    dynamic var progressBarTint: UIColor? {
        get { return progressBar.progressTintColor }
        set { progressBar.progressTintColor = newValue }
    }

    dynamic var cancelTextColor: UIColor? {
        get { return cancelButton.titleColorForState(UIControlState.Normal) }
        set { return cancelButton.setTitleColor(newValue, forState: UIControlState.Normal) }
    }

    dynamic var actionButtonTintColor: UIColor? {
        get { return helper?.buttonTintColor }
        set {
            guard let value = newValue else { return }
            helper?.buttonTintColor = value
        }
    }

}

extension URLBarView: Themeable {
    
    func applyTheme(themeName: String) {
        locationView.applyTheme(themeName)
        locationTextField?.applyTheme(themeName)

        guard let theme = URLBarViewUX.Themes[themeName] else {
            log.error("Unable to apply unknown theme \(themeName)")
            return
        }

        currentTheme = themeName
        locationBorderColor = theme.borderColor!
        locationActiveBorderColor = theme.activeBorderColor!
        progressBarTint = theme.tintColor
        cancelTextColor = theme.textColor
        actionButtonTintColor = theme.buttonTintColor

        tabsButton.applyTheme(themeName)
    }
}

extension URLBarView: AppStateDelegate {
    func appDidUpdateState(appState: AppState) {
        if toolbarIsShowing {
            let showShareButton = HomePageAccessors.isButtonInMenu(appState)
            homePageButton.hidden = showShareButton
            shareButton.hidden = !showShareButton || inOverlayMode
            homePageButton.enabled = HomePageAccessors.isButtonEnabled(appState)
        } else {
            homePageButton.hidden = true
            shareButton.hidden = true
        }
    }
}

/* Code for drawing the urlbar curve */
// Curve's aspect ratio
private let ASPECT_RATIO = 0.729

// Width multipliers
private let W_M1 = 0.343
private let W_M2 = 0.514
private let W_M3 = 0.49
private let W_M4 = 0.545
private let W_M5 = 0.723

// Height multipliers
private let H_M1 = 0.25
private let H_M2 = 0.5
private let H_M3 = 0.72
private let H_M4 = 0.961

/* Code for drawing the urlbar curve */
private class CurveView: UIView {
    private lazy var leftCurvePath: UIBezierPath = {
        var leftArc = UIBezierPath(arcCenter: CGPoint(x: 5, y: 5), radius: CGFloat(5), startAngle: CGFloat(-M_PI), endAngle: CGFloat(-M_PI_2), clockwise: true)
        leftArc.addLineToPoint(CGPoint(x: 0, y: 0))
        leftArc.addLineToPoint(CGPoint(x: 0, y: 5))
        leftArc.closePath()
        return leftArc
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        self.opaque = false
        self.contentMode = .Redraw
    }

    private func getWidthForHeight(height: Double) -> Double {
        return height * ASPECT_RATIO
    }

    private func drawFromTop(path: UIBezierPath) {
        let height: Double = Double(UIConstants.ToolbarHeight)
        let width = getWidthForHeight(height)
        let from = (Double(self.frame.width) - width * 2 - Double(URLBarViewUX.URLBarCurveOffset - URLBarViewUX.URLBarCurveBounceBuffer), Double(0))

        path.moveToPoint(CGPoint(x: from.0, y: from.1))
        path.addCurveToPoint(CGPoint(x: from.0 + width * W_M2, y: from.1 + height * H_M2),
              controlPoint1: CGPoint(x: from.0 + width * W_M1, y: from.1),
              controlPoint2: CGPoint(x: from.0 + width * W_M3, y: from.1 + height * H_M1))

        path.addCurveToPoint(CGPoint(x: from.0 + width, y: from.1 + height),
              controlPoint1: CGPoint(x: from.0 + width * W_M4, y: from.1 + height * H_M3),
              controlPoint2: CGPoint(x: from.0 + width * W_M5, y: from.1 + height * H_M4))
    }

    private func getPath() -> UIBezierPath {
        let path = UIBezierPath()
        self.drawFromTop(path)
        path.addLineToPoint(CGPoint(x: self.frame.width, y: UIConstants.ToolbarHeight))
        path.addLineToPoint(CGPoint(x: self.frame.width, y: 0))
        path.addLineToPoint(CGPoint(x: 0, y: 0))
        path.closePath()
        return path
    }

    override func drawRect(rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        CGContextSaveGState(context)
        CGContextClearRect(context, rect)
        CGContextSetFillColorWithColor(context, URLBarViewUX.backgroundColorWithAlpha(1).CGColor)
        getPath().fill()
        leftCurvePath.fill()
        CGContextDrawPath(context, CGPathDrawingMode.Fill)
        CGContextRestoreGState(context)
    }
}

class ToolbarTextField: AutocompleteTextField {
    static let Themes: [String: Theme] = {
        var themes = [String: Theme]()
        var theme = Theme()
        theme.backgroundColor = UIConstants.PrivateModeLocationBackgroundColor
        theme.textColor = UIColor.whiteColor()
        theme.buttonTintColor = UIColor.whiteColor()
        theme.highlightColor = UIConstants.PrivateModeInputHighlightColor
        themes[Theme.PrivateMode] = theme

        theme = Theme()
        theme.backgroundColor = UIColor.whiteColor()
        theme.textColor = UIColor.blackColor()
        theme.highlightColor = AutocompleteTextFieldUX.HighlightColor
        themes[Theme.NormalMode] = theme

        return themes
    }()

    dynamic var clearButtonTintColor: UIColor? {
        didSet {
            // Clear previous tinted image that's cache and ask for a relayout
            tintedClearImage = nil
            setNeedsLayout()
        }
    }

    private var tintedClearImage: UIImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Since we're unable to change the tint color of the clear image, we need to iterate through the
        // subviews, find the clear button, and tint it ourselves. Thanks to Mikael Hellman for the tip:
        // http://stackoverflow.com/questions/27944781/how-to-change-the-tint-color-of-the-clear-button-on-a-uitextfield
        for view in subviews as [UIView] {
            if let button = view as? UIButton {
                if let image = button.imageForState(.Normal) {
                    if tintedClearImage == nil {
                        tintedClearImage = tintImage(image, color: clearButtonTintColor)
                    }

                    if button.imageView?.image != tintedClearImage {
                        button.setImage(tintedClearImage, forState: .Normal)
                    }
                }
            }
        }
    }

    private func tintImage(image: UIImage, color: UIColor?) -> UIImage {
        guard let color = color else { return image }

        let size = image.size

        UIGraphicsBeginImageContextWithOptions(size, false, 2)
        let context = UIGraphicsGetCurrentContext()
        image.drawAtPoint(CGPointZero, blendMode: CGBlendMode.Normal, alpha: 1.0)

        CGContextSetFillColorWithColor(context, color.CGColor)
        CGContextSetBlendMode(context, CGBlendMode.SourceIn)
        CGContextSetAlpha(context, 1.0)

        let rect = CGRectMake(
            CGPointZero.x,
            CGPointZero.y,
            image.size.width,
            image.size.height)
        CGContextFillRect(UIGraphicsGetCurrentContext(), rect)
        let tintedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return tintedImage
    }
}

extension ToolbarTextField: Themeable {
    func applyTheme(themeName: String) {
        guard let theme = ToolbarTextField.Themes[themeName] else {
            log.error("Unable to apply unknown theme \(themeName)")
            return
        }

        backgroundColor = theme.backgroundColor
        textColor = theme.textColor
        clearButtonTintColor = theme.buttonTintColor
        highlightColor = theme.highlightColor!
    }
}
