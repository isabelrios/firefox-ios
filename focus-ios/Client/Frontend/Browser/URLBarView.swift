/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import Shared
import SnapKit

private struct URLBarViewUX {
    static let TextFieldBorderColor = UIColor(rgb: 0xBBBBBB)
    static let TextFieldActiveBorderColor = UIColor(rgb: 0x4A90E2)
    static let TextFieldContentInset = UIOffsetMake(9, 5)
    static let LocationLeftPadding = 5
    static let LocationHeight = 28
    static let LocationContentOffset: CGFloat = 8
    static let TextFieldCornerRadius: CGFloat = 3
    static let TextFieldBorderWidth: CGFloat = 1
    // offset from edge of tabs button
    static let URLBarCurveOffset: CGFloat = 14
    static let URLBarCurveOffsetLeft: CGFloat = -10
    // buffer so we dont see edges when animation overshoots with spring
    static let URLBarCurveBounceBuffer: CGFloat = 8

    static let TabsButtonRotationOffset: CGFloat = 1.5
    static let TabsButtonHeight: CGFloat = 18.0
    static let ToolbarButtonInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

    static func backgroundColorWithAlpha(alpha: CGFloat) -> UIColor {
        return UIConstants.AppBackgroundColor.colorWithAlphaComponent(alpha)
    }
}

protocol URLBarDelegate: class {
    func urlBarDidPressTabs(urlBar: URLBarView)
    func urlBarDidPressReaderMode(urlBar: URLBarView)
    /// :returns: whether the long-press was handled by the delegate; i.e. return `false` when the conditions for even starting handling long-press were not satisfied
    func urlBarDidLongPressReaderMode(urlBar: URLBarView) -> Bool
    func urlBarDidPressStop(urlBar: URLBarView)
    func urlBarDidPressReload(urlBar: URLBarView)
    func urlBarDidEnterOverlayMode(urlBar: URLBarView)
    func urlBarDidLeaveOverlayMode(urlBar: URLBarView)
    func urlBarDidLongPressLocation(urlBar: URLBarView)
    func urlBarLocationAccessibilityActions(urlBar: URLBarView) -> [UIAccessibilityCustomAction]?
    func urlBarDidPressScrollToTop(urlBar: URLBarView)
    func urlBar(urlBar: URLBarView, didEnterText text: String)
    func urlBar(urlBar: URLBarView, didSubmitText text: String)
}

class URLBarView: UIView {
    weak var delegate: URLBarDelegate?
    weak var browserToolbarDelegate: BrowserToolbarDelegate?
    var helper: BrowserToolbarHelper?

    var toolbarIsShowing = false

    /// Overlay mode is the state where the lock/reader icons are hidden, the home panels are shown,
    /// and the Cancel button is visible (allowing the user to leave overlay mode). Overlay mode
    /// is *not* tied to the location text field's editing state; for instance, when selecting
    /// a panel, the first responder will be resigned, yet the overlay mode UI is still active.
    var inOverlayMode = false

    lazy var locationView: BrowserLocationView = {
        let locationView = BrowserLocationView()
        locationView.setTranslatesAutoresizingMaskIntoConstraints(false)
        locationView.readerModeState = ReaderModeState.Unavailable
        locationView.delegate = self
        return locationView
    }()

    private lazy var locationTextField: ToolbarTextField = {
        let locationTextField = ToolbarTextField()
        locationTextField.setTranslatesAutoresizingMaskIntoConstraints(false)
        locationTextField.autocompleteDelegate = self
        locationTextField.keyboardType = UIKeyboardType.WebSearch
        locationTextField.autocorrectionType = UITextAutocorrectionType.No
        locationTextField.autocapitalizationType = UITextAutocapitalizationType.None
        locationTextField.returnKeyType = UIReturnKeyType.Go
        locationTextField.clearButtonMode = UITextFieldViewMode.WhileEditing
        locationTextField.backgroundColor = UIColor.whiteColor()
        locationTextField.font = UIConstants.DefaultMediumFont
        locationTextField.accessibilityIdentifier = "address"
        locationTextField.accessibilityLabel = NSLocalizedString("Address and Search", comment: "Accessibility label for address and search field, both words (Address, Search) are therefore nouns.")
        locationTextField.attributedPlaceholder = self.locationView.placeholder
        return locationTextField
    }()

    private lazy var locationContainer: UIView = {
        let locationContainer = UIView()
        locationContainer.setTranslatesAutoresizingMaskIntoConstraints(false)

        // Enable clipping to apply the rounded edges to subviews.
        locationContainer.clipsToBounds = true

        locationContainer.layer.borderColor = URLBarViewUX.TextFieldBorderColor.CGColor
        locationContainer.layer.cornerRadius = URLBarViewUX.TextFieldCornerRadius
        locationContainer.layer.borderWidth = URLBarViewUX.TextFieldBorderWidth

        return locationContainer
    }()

    private lazy var tabsButton: UIButton = {
        let tabsButton = InsetButton()
        tabsButton.setTranslatesAutoresizingMaskIntoConstraints(false)
        tabsButton.setTitle("0", forState: UIControlState.Normal)
        tabsButton.setTitleColor(URLBarViewUX.backgroundColorWithAlpha(1), forState: UIControlState.Normal)
        tabsButton.titleLabel?.layer.backgroundColor = UIColor.whiteColor().CGColor
        tabsButton.titleLabel?.layer.cornerRadius = 2
        tabsButton.titleLabel?.font = UIConstants.DefaultSmallFontBold
        tabsButton.titleLabel?.textAlignment = NSTextAlignment.Center
        tabsButton.setContentHuggingPriority(1000, forAxis: UILayoutConstraintAxis.Horizontal)
        tabsButton.setContentCompressionResistancePriority(1000, forAxis: UILayoutConstraintAxis.Horizontal)
        tabsButton.addTarget(self, action: "SELdidClickAddTab", forControlEvents: UIControlEvents.TouchUpInside)
        tabsButton.accessibilityLabel = NSLocalizedString("Show Tabs", comment: "Accessibility Label for the tabs button in the browser toolbar")
        return tabsButton
    }()

    private lazy var progressBar: UIProgressView = {
        let progressBar = UIProgressView()
        progressBar.progressTintColor = UIColor(red:1, green:0.32, blue:0, alpha:1)
        progressBar.alpha = 0
        progressBar.hidden = true
        return progressBar
    }()

    private lazy var cancelButton: UIButton = {
        let cancelButton = InsetButton()
        cancelButton.setTitleColor(UIColor.blackColor(), forState: UIControlState.Normal)
        let cancelTitle = NSLocalizedString("Cancel", comment: "Button label to cancel entering a URL or search query")
        cancelButton.setTitle(cancelTitle, forState: UIControlState.Normal)
        cancelButton.titleLabel?.font = UIConstants.DefaultMediumFont
        cancelButton.addTarget(self, action: "SELdidClickCancel", forControlEvents: UIControlEvents.TouchUpInside)
        cancelButton.titleEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12)
        cancelButton.setContentHuggingPriority(1000, forAxis: UILayoutConstraintAxis.Horizontal)
        cancelButton.setContentCompressionResistancePriority(1000, forAxis: UILayoutConstraintAxis.Horizontal)
        return cancelButton
    }()

    private lazy var curveShape: CurveView = { return CurveView() }()

    private lazy var scrollToTopButton: UIButton = {
        let button = UIButton()
        button.addTarget(self, action: "SELtappedScrollToTopArea", forControlEvents: UIControlEvents.TouchUpInside)
        return button
    }()

    lazy var shareButton: UIButton = { return UIButton() }()

    lazy var bookmarkButton: UIButton = { return UIButton() }()

    lazy var forwardButton: UIButton = { return UIButton() }()

    lazy var backButton: UIButton = { return UIButton() }()

    lazy var stopReloadButton: UIButton = { return UIButton() }()

    lazy var actionButtons: [UIButton] = {
        return [self.shareButton, self.bookmarkButton, self.forwardButton, self.backButton, self.stopReloadButton]
    }()

    // Used to temporarily store the cloned button so we can respond to layout changes during animation
    private weak var clonedTabsButton: InsetButton?

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

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = URLBarViewUX.backgroundColorWithAlpha(0)
        addSubview(curveShape)
        addSubview(scrollToTopButton)

        locationContainer.addSubview(locationView)
        locationContainer.addSubview(locationTextField)
        addSubview(locationContainer)

        addSubview(progressBar)
        addSubview(tabsButton)
        addSubview(cancelButton)

        addSubview(shareButton)
        addSubview(bookmarkButton)
        addSubview(forwardButton)
        addSubview(backButton)
        addSubview(stopReloadButton)

        helper = BrowserToolbarHelper(toolbar: self)
        setupConstraints()

        // Make sure we hide any views that shouldn't be showing in non-overlay mode.
        updateViewsForOverlayModeAndToolbarChanges()
    }

    private func setupConstraints() {
        scrollToTopButton.snp_makeConstraints { make in
            make.top.equalTo(self)
            make.left.right.equalTo(self.locationContainer)
        }

        progressBar.snp_makeConstraints { make in
            make.top.equalTo(self.snp_bottom)
            make.width.equalTo(self)
        }

        locationView.snp_makeConstraints { make in
            make.edges.equalTo(self.locationContainer)
        }

        cancelButton.snp_makeConstraints { make in
            make.centerY.equalTo(self.locationContainer)
            make.trailing.equalTo(self)
        }

        tabsButton.titleLabel?.snp_makeConstraints { make in
            make.size.equalTo(URLBarViewUX.TabsButtonHeight)
        }

        tabsButton.snp_makeConstraints { make in
            make.centerY.equalTo(self.locationContainer)
            make.trailing.equalTo(self)
            make.width.height.equalTo(UIConstants.ToolbarHeight)
        }

        curveShape.snp_makeConstraints { make in
            make.top.left.bottom.equalTo(self)
            self.rightBarConstraint = make.right.equalTo(self).constraint
            self.rightBarConstraint?.updateOffset(defaultRightOffset)
        }

        locationTextField.snp_makeConstraints { make in
            make.edges.equalTo(self.locationView.urlTextField)
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

                make.height.equalTo(URLBarViewUX.LocationHeight)
                make.centerY.equalTo(self)
            }
        }

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

    func updateAlphaForSubviews(alpha: CGFloat) {
        self.tabsButton.alpha = alpha
        self.locationContainer.alpha = alpha
        self.backgroundColor = URLBarViewUX.backgroundColorWithAlpha(1 - alpha)
        self.actionButtons.map { $0.alpha = alpha }
    }

    func updateTabCount(count: Int) {
        // make a 'clone' of the tabs button
        let newTabsButton = InsetButton()
        self.clonedTabsButton = newTabsButton
        newTabsButton.addTarget(self, action: "SELdidClickAddTab", forControlEvents: UIControlEvents.TouchUpInside)
        newTabsButton.setTitleColor(UIConstants.AppBackgroundColor, forState: UIControlState.Normal)
        newTabsButton.titleLabel?.layer.backgroundColor = UIColor.whiteColor().CGColor
        newTabsButton.titleLabel?.layer.cornerRadius = 2
        newTabsButton.titleLabel?.font = UIConstants.DefaultSmallFontBold
        newTabsButton.titleLabel?.textAlignment = NSTextAlignment.Center
        newTabsButton.setTitle(count.description, forState: .Normal)
        addSubview(newTabsButton)
        newTabsButton.titleLabel?.snp_makeConstraints { make in
            make.size.equalTo(URLBarViewUX.TabsButtonHeight)
        }
        newTabsButton.snp_makeConstraints { make in
            make.centerY.equalTo(self.locationContainer)
            make.trailing.equalTo(self)
            make.size.equalTo(UIConstants.ToolbarHeight)
        }

        newTabsButton.frame = tabsButton.frame

        // Instead of changing the anchorPoint of the CALayer, lets alter the rotation matrix math to be
        // a rotation around a non-origin point
        if let labelFrame = newTabsButton.titleLabel?.frame {
            let halfTitleHeight = CGRectGetHeight(labelFrame) / 2

            var newFlipTransform = CATransform3DIdentity
            newFlipTransform = CATransform3DTranslate(newFlipTransform, 0, halfTitleHeight, 0)
            newFlipTransform.m34 = -1.0 / 200.0 // add some perspective
            newFlipTransform = CATransform3DRotate(newFlipTransform, CGFloat(-M_PI_2), 1.0, 0.0, 0.0)
            newTabsButton.titleLabel?.layer.transform = newFlipTransform

            var oldFlipTransform = CATransform3DIdentity
            oldFlipTransform = CATransform3DTranslate(oldFlipTransform, 0, halfTitleHeight, 0)
            oldFlipTransform.m34 = -1.0 / 200.0 // add some perspective
            oldFlipTransform = CATransform3DRotate(oldFlipTransform, CGFloat(M_PI_2), 1.0, 0.0, 0.0)

            UIView.animateWithDuration(1.5, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.0, options: UIViewAnimationOptions.CurveEaseInOut, animations: { _ in
                newTabsButton.titleLabel?.layer.transform = CATransform3DIdentity
                self.tabsButton.titleLabel?.layer.transform = oldFlipTransform
                self.tabsButton.titleLabel?.layer.opacity = 0
                }, completion: { _ in
                    // remove the clone and setup the actual tab button
                    newTabsButton.removeFromSuperview()

                    self.tabsButton.titleLabel?.layer.opacity = 1
                    self.tabsButton.titleLabel?.layer.transform = CATransform3DIdentity
                    self.tabsButton.setTitle(count.description, forState: UIControlState.Normal)
                    self.tabsButton.accessibilityValue = count.description
                    self.tabsButton.accessibilityLabel = NSLocalizedString("Show Tabs", comment: "Accessibility label for the tabs button in the (top) browser toolbar")
            })
        }
    }

    func updateProgressBar(progress: Float) {
        if progress == 1.0 {
            self.progressBar.setProgress(progress, animated: true)
            UIView.animateWithDuration(1.5, animations: {
                self.progressBar.alpha = 0.0
            }, completion: { _ in
                self.progressBar.setProgress(0.0, animated: false)
            })
        } else {
            self.progressBar.alpha = 1.0
            self.progressBar.setProgress(progress, animated: (progress > progressBar.progress))
        }
    }

    func updateReaderModeState(state: ReaderModeState) {
        locationView.readerModeState = state
    }

    func setAutocompleteSuggestion(suggestion: String?) {
        locationTextField.setAutocompleteSuggestion(suggestion)
    }

    func enterOverlayMode(locationText: String?, pasted: Bool) {
        if pasted {
            // Clear any existing text, focus the field, then set the actual pasted text.
            // This avoids highlighting all of the text.
            locationTextField.text = ""
            locationTextField.becomeFirstResponder()
            locationTextField.text = locationText
        } else {
            // Copy the current URL to the editable text field, then activate it.
            locationTextField.text = locationText
            locationTextField.becomeFirstResponder()
        }

        // Show the overlay mode UI, which includes hiding the locationView and replacing it
        // with the editable locationTextField.
        animateToOverlayState(true)

        delegate?.urlBarDidEnterOverlayMode(self)
    }

    func leaveOverlayMode() {
        locationTextField.resignFirstResponder()
        animateToOverlayState(false)
        delegate?.urlBarDidLeaveOverlayMode(self)
    }

    func prepareOverlayAnimation() {
        // Make sure everything is showing during the transition (we'll hide it afterwards).
        self.cancelButton.hidden = false
        self.progressBar.hidden = false
        self.locationTextField.hidden = false
        self.shareButton.hidden = !self.toolbarIsShowing
        self.bookmarkButton.hidden = !self.toolbarIsShowing
        self.forwardButton.hidden = !self.toolbarIsShowing
        self.backButton.hidden = !self.toolbarIsShowing
        self.stopReloadButton.hidden = !self.toolbarIsShowing
    }

    func transitionToOverlay() {
        self.cancelButton.alpha = inOverlayMode ? 1 : 0
        self.progressBar.alpha = inOverlayMode ? 0 : 1
        self.locationTextField.alpha = inOverlayMode ? 1 : 0
        self.shareButton.alpha = inOverlayMode ? 0 : 1
        self.bookmarkButton.alpha = inOverlayMode ? 0 : 1
        self.forwardButton.alpha = inOverlayMode ? 0 : 1
        self.backButton.alpha = inOverlayMode ? 0 : 1
        self.stopReloadButton.alpha = inOverlayMode ? 0 : 1

        let borderColor = inOverlayMode ? URLBarViewUX.TextFieldActiveBorderColor : URLBarViewUX.TextFieldBorderColor
        locationContainer.layer.borderColor = borderColor.CGColor

        if inOverlayMode {
            self.cancelButton.transform = CGAffineTransformIdentity
            let tabsButtonTransform = CGAffineTransformMakeTranslation(self.tabsButton.frame.width + URLBarViewUX.URLBarCurveOffset, 0)
            self.tabsButton.transform = tabsButtonTransform
            self.clonedTabsButton?.transform = tabsButtonTransform
            self.rightBarConstraint?.updateOffset(URLBarViewUX.URLBarCurveOffset + URLBarViewUX.URLBarCurveBounceBuffer + tabsButton.frame.width)

            // Make the editable text field span the entire URL bar, covering the lock and reader icons.
            self.locationTextField.snp_remakeConstraints { make in
                make.leading.equalTo(self.locationContainer).offset(URLBarViewUX.LocationContentOffset)
                make.top.bottom.trailing.equalTo(self.locationContainer)
            }
        } else {
            self.tabsButton.transform = CGAffineTransformIdentity
            self.clonedTabsButton?.transform = CGAffineTransformIdentity
            self.cancelButton.transform = CGAffineTransformMakeTranslation(self.cancelButton.frame.width, 0)
            self.rightBarConstraint?.updateOffset(defaultRightOffset)

            // Shrink the editable text field back to the size of the location view before hiding it.
            self.locationTextField.snp_remakeConstraints { make in
                make.edges.equalTo(self.locationView.urlTextField)
            }
        }
    }

    func updateViewsForOverlayModeAndToolbarChanges() {
        self.cancelButton.hidden = !inOverlayMode
        self.progressBar.hidden = inOverlayMode
        self.locationTextField.hidden = !inOverlayMode
        self.shareButton.hidden = !self.toolbarIsShowing || inOverlayMode
        self.bookmarkButton.hidden = !self.toolbarIsShowing || inOverlayMode
        self.forwardButton.hidden = !self.toolbarIsShowing || inOverlayMode
        self.backButton.hidden = !self.toolbarIsShowing || inOverlayMode
        self.stopReloadButton.hidden = !self.toolbarIsShowing || inOverlayMode
    }

    func animateToOverlayState(overlay: Bool) {
        prepareOverlayAnimation()
        layoutIfNeeded()

        inOverlayMode = overlay

        UIView.animateWithDuration(0.3, delay: 0.0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.0, options: nil, animations: { _ in
            self.transitionToOverlay()
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
        leaveOverlayMode()
    }

    func SELtappedScrollToTopArea() {
        delegate?.urlBarDidPressScrollToTop(self)
    }
}

extension URLBarView: BrowserToolbarProtocol {
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
        if isLoading {
            stopReloadButton.setImage(helper?.ImageStop, forState: .Normal)
            stopReloadButton.setImage(helper?.ImageStopPressed, forState: .Highlighted)
        } else {
            stopReloadButton.setImage(helper?.ImageReload, forState: .Normal)
            stopReloadButton.setImage(helper?.ImageReloadPressed, forState: .Highlighted)
        }
    }

    func updatePageStatus(#isWebPage: Bool) {
        bookmarkButton.enabled = isWebPage
        stopReloadButton.enabled = isWebPage
        shareButton.enabled = isWebPage
    }

    override var accessibilityElements: [AnyObject]! {
        get {
            if inOverlayMode {
                return [locationTextField, cancelButton]
            } else {
                if toolbarIsShowing {
                    return [backButton, forwardButton, stopReloadButton, locationView, shareButton, bookmarkButton, tabsButton, progressBar]
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

extension URLBarView: BrowserLocationViewDelegate {
    func browserLocationViewDidLongPressReaderMode(browserLocationView: BrowserLocationView) -> Bool {
        return delegate?.urlBarDidLongPressReaderMode(self) ?? false
    }

    func browserLocationViewDidTapLocation(browserLocationView: BrowserLocationView) {
        enterOverlayMode(locationView.url?.absoluteString, pasted: false)
    }

    func browserLocationViewDidLongPressLocation(browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidLongPressLocation(self)
    }

    func browserLocationViewDidTapReload(browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidPressReload(self)
    }
    
    func browserLocationViewDidTapStop(browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidPressStop(self)
    }

    func browserLocationViewDidTapReaderMode(browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidPressReaderMode(self)
    }

    func browserLocationViewLocationAccessibilityActions(browserLocationView: BrowserLocationView) -> [UIAccessibilityCustomAction]? {
        return delegate?.urlBarLocationAccessibilityActions(self)
    }
}

extension URLBarView: AutocompleteTextFieldDelegate {
    func autocompleteTextFieldShouldReturn(autocompleteTextField: AutocompleteTextField) -> Bool {
        delegate?.urlBar(self, didSubmitText: locationTextField.text)
        return true
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

    required init(coder aDecoder: NSCoder) {
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
        var from = (Double(self.frame.width) - width * 2 - Double(URLBarViewUX.URLBarCurveOffset - URLBarViewUX.URLBarCurveBounceBuffer), Double(0))

        path.moveToPoint(CGPoint(x: from.0, y: from.1))
        path.addCurveToPoint(CGPoint(x: from.0 + width * W_M2, y: from.1 + height * H_M2),
              controlPoint1: CGPoint(x: from.0 + width * W_M1, y: from.1),
              controlPoint2: CGPoint(x: from.0 + width * W_M3, y: from.1 + height * H_M1))

        path.addCurveToPoint(CGPoint(x: from.0 + width,        y: from.1 + height),
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
        CGContextDrawPath(context, kCGPathFill)
        CGContextRestoreGState(context)
    }
}

private class ToolbarTextField: AutocompleteTextField {
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
