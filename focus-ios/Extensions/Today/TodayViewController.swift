/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import NotificationCenter
import Shared
import SnapKit
import XCGLogger

private let log = Logger.browserLogger

struct TodayStrings {
    static let NewPrivateTabButtonLabel = NSLocalizedString("TodayWidget.NewPrivateTabButtonLabel", tableName: "Today", value: "Private Search", comment: "New Private Tab button label")
    static let NewTabButtonLabel = NSLocalizedString("TodayWidget.NewTabButtonLabel", tableName: "Today", value: "New Search", comment: "New Tab button label")
    static let GoToCopiedLinkLabel = NSLocalizedString("TodayWidget.GoToCopiedLinkLabel", tableName: "Today", value: "Go to copied link", comment: "Go to link on clipboard")
}

private struct TodayUX {
    static let backgroundHightlightColor = UIColor(white: 216.0/255.0, alpha: 44.0/255.0)
    static let linkTextSize: CGFloat = 9.0
    static let labelTextSize: CGFloat = 12.0
    static let imageButtonTextSize: CGFloat = 13.0
    static let copyLinkImageWidth: CGFloat = 20
    static let margin: CGFloat = 8
    static let buttonsHorizontalMarginPercentage: CGFloat = 0.1
    static let buttonStackViewSpacing: CGFloat = 30.0
    static var labelColor: UIColor {
        if #available(iOS 13, *) {
            return UIColor(named: "widgetLabelColors") ?? UIColor(rgb: 0x242327)
        } else {
            return UIColor(rgb: 0x242327)
        }
    }
    static var subtitleLabelColor: UIColor {
        if #available(iOS 13, *) {
            return UIColor(named: "subtitleLableColor") ?? UIColor(rgb: 0x38383C)
        } else {
            return UIColor(rgb: 0x38383C)
        }
    }
}

@objc (TodayViewController)
class TodayViewController: UIViewController, NCWidgetProviding {
    var copiedURL: URL?

    fileprivate lazy var newTabButton: ImageButtonWithLabel = {
        let imageButton = ImageButtonWithLabel()
        imageButton.addTarget(self, action: #selector(onPressNewTab), forControlEvents: .touchUpInside)
        imageButton.label.text = TodayStrings.NewTabButtonLabel
        let button = imageButton.button
        button.setImage(UIImage(named: "search-button")?.withRenderingMode(.alwaysOriginal), for: .normal)
        let label = imageButton.label
        label.textColor = TodayUX.labelColor
        label.tintColor = TodayUX.labelColor
        label.font = UIFont.systemFont(ofSize: TodayUX.imageButtonTextSize)
        imageButton.sizeToFit()
        return imageButton
    }()

    fileprivate lazy var newPrivateTabButton: ImageButtonWithLabel = {
        let imageButton = ImageButtonWithLabel()
        imageButton.addTarget(self, action: #selector(onPressNewPrivateTab), forControlEvents: .touchUpInside)
        imageButton.label.text = TodayStrings.NewPrivateTabButtonLabel
        let button = imageButton.button
        button.setImage(UIImage(named: "private-search")?.withRenderingMode(.alwaysOriginal), for: .normal)
        let label = imageButton.label
        label.textColor = TodayUX.labelColor
        label.tintColor = TodayUX.labelColor
        label.font = UIFont.systemFont(ofSize: TodayUX.imageButtonTextSize)
        imageButton.sizeToFit()
        return imageButton
    }()

    fileprivate lazy var openCopiedLinkButton: ButtonWithSublabel = {
        let button = ButtonWithSublabel()
        button.setTitle(TodayStrings.GoToCopiedLinkLabel, for: .normal)
        button.addTarget(self, action: #selector(onPressOpenClibpoard), for: .touchUpInside)
        // We need to set the background image/color for .Normal, so the whole button is tappable.
        button.setBackgroundColor(UIColor.clear, forState: .normal)
        button.setBackgroundColor(TodayUX.backgroundHightlightColor, forState: .highlighted)
        button.setImage(UIImage(named: "copy_link_icon")?.withRenderingMode(.alwaysOriginal), for: .normal)
        button.label.font = UIFont.systemFont(ofSize: TodayUX.labelTextSize)
        button.subtitleLabel.font = UIFont.systemFont(ofSize: TodayUX.linkTextSize)
        button.label.textColor = TodayUX.labelColor
        button.label.tintColor = TodayUX.labelColor
        button.subtitleLabel.textColor = TodayUX.subtitleLabelColor
        button.subtitleLabel.tintColor = TodayUX.subtitleLabelColor
        return button
    }()

    fileprivate lazy var widgetStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = TodayUX.margin / 2
        stackView.distribution = UIStackView.Distribution.fillProportionally
        return stackView
    }()

    fileprivate lazy var buttonStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = TodayUX.buttonStackViewSpacing
        stackView.distribution = UIStackView.Distribution.fillEqually
        return stackView
    }()

    fileprivate var scheme: String {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "MozInternalURLScheme") as? String else {
            // Something went wrong/weird, but we should fallback to the public one.
            return "firefox"
        }
        return string
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let widgetView: UIView!
        self.extensionContext?.widgetLargestAvailableDisplayMode = .compact

        let effectView: UIVisualEffectView

        if #available(iOS 13, *) {
            effectView = UIVisualEffectView(effect: UIVibrancyEffect.widgetEffect(forVibrancyStyle: .label))
        } else {
            effectView = UIVisualEffectView(effect: .none)
        }

        self.view.addSubview(effectView)
        effectView.snp.makeConstraints { make in
            make.edges.equalTo(self.view)
        }
        widgetView = effectView.contentView
        buttonStackView.addArrangedSubview(newTabButton)
        buttonStackView.addArrangedSubview(newPrivateTabButton)

        widgetStackView.addArrangedSubview(buttonStackView)
        widgetStackView.addArrangedSubview(openCopiedLinkButton)

        widgetView.addSubview(widgetStackView)
        widgetStackView.snp.makeConstraints { make in
            make.edges.equalTo(widgetView)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateCopiedLink()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let edge = size.width * TodayUX.buttonsHorizontalMarginPercentage
        buttonStackView.layoutMargins = UIEdgeInsets(top: 0, left: edge, bottom: 0, right: edge)
    }

    func widgetMarginInsets(forProposedMarginInsets defaultMarginInsets: UIEdgeInsets) -> UIEdgeInsets {
        return .zero
    }

    func updateCopiedLink() {
        UIPasteboard.general.asyncURL().uponQueue(.main) { res in
            if let copiedURL: URL? = res.successValue,
                let url = copiedURL {
                self.openCopiedLinkButton.isHidden = false
                self.openCopiedLinkButton.subtitleLabel.isHidden = SystemUtils.isDeviceLocked()
                self.openCopiedLinkButton.subtitleLabel.text = url.absoluteDisplayString
                self.copiedURL = url
            } else {
                self.openCopiedLinkButton.isHidden = true
                self.copiedURL = nil
            }
        }
    }

    // MARK: Button behaviour
    @objc func onPressNewTab(_ view: UIView) {
        openContainingApp("?private=false")
    }

    @objc func onPressNewPrivateTab(_ view: UIView) {
        openContainingApp("?private=true")
    }

    fileprivate func openContainingApp(_ urlSuffix: String = "") {
        let urlString = "\(scheme)://open-url\(urlSuffix)"
        self.extensionContext?.open(URL(string: urlString)!) { success in
            log.info("Extension opened containing app: \(success)")
        }
    }

    @objc func onPressOpenClibpoard(_ view: UIView) {
        if let url = copiedURL,
            let encodedString = url.absoluteString.escape() {
            openContainingApp("?url=\(encodedString)")
        }
    }
}

extension UIButton {
    func setBackgroundColor(_ color: UIColor, forState state: UIControl.State) {
        let colorView = UIView(frame: CGRect(width: 1, height: 1))
        colorView.backgroundColor = color

        UIGraphicsBeginImageContext(colorView.bounds.size)
        if let context = UIGraphicsGetCurrentContext() {
            colorView.layer.render(in: context)
        }
        let colorImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        self.setBackgroundImage(colorImage, for: state)
    }
}

class ImageButtonWithLabel: UIView {

    lazy var button = UIButton()
    lazy var label = UILabel()

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        performLayout()
    }

    func performLayout() {
        addSubview(button)
        addSubview(label)
        button.imageView?.contentMode = .scaleAspectFit

        button.snp.makeConstraints { make in
            make.centerX.equalTo(self)
            make.top.equalTo(self.safeAreaLayoutGuide).offset(5)
            make.right.greaterThanOrEqualTo(self.safeAreaLayoutGuide).offset(40)
            make.left.greaterThanOrEqualTo(self.safeAreaLayoutGuide).inset(40)
            make.height.greaterThanOrEqualTo(60)
        }

        label.snp.makeConstraints { make in
            make.top.equalTo(button.snp.bottom).offset(10)
            make.leading.trailing.bottom.equalTo(self)
            make.height.equalTo(10)
        }

        label.numberOfLines = 1
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
    }

    func addTarget(_ target: AnyObject?, action: Selector, forControlEvents events: UIControl.Event) {
        button.addTarget(target, action: action, for: events)
    }
}

class ButtonWithSublabel: UIButton {
    lazy var subtitleLabel = UILabel()
    lazy var label = UILabel()

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        performLayout()
    }

    fileprivate func performLayout() {
        let titleLabel = self.label
        self.titleLabel?.removeFromSuperview()
        addSubview(titleLabel)

        let imageView = self.imageView!
        let subtitleLabel = self.subtitleLabel
        self.addSubview(subtitleLabel)

        imageView.snp.makeConstraints { make in
            make.centerY.left.equalTo(10)
            make.width.equalTo(TodayUX.copyLinkImageWidth)
        }

        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(imageView.snp.right).offset(10)
            make.trailing.top.equalTo(self)
            make.height.greaterThanOrEqualTo(12)
        }

        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.snp.makeConstraints { make in
            make.bottom.equalTo(self).inset(10)
            make.top.equalTo(titleLabel.snp.bottom)
            make.leading.trailing.equalTo(titleLabel)
            make.height.greaterThanOrEqualTo(10)
        }
    }

    override func setTitle(_ text: String?, for state: UIControl.State) {
        self.label.text = text
        super.setTitle(text, for: state)
    }
}
