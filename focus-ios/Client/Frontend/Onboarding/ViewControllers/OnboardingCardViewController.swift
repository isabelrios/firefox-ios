// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import Common
import Shared

class OnboardingCardViewController: UIViewController, Themeable {
    struct UX {
        static let stackViewSpacing: CGFloat = 24
        static let stackViewSpacingButtons: CGFloat = 16
        static let buttonCornerRadius: CGFloat = 13
        static let topStackViewSpacing: CGFloat = 24
        static let topStackViewPaddingPad: CGFloat = 70
        static let topStackViewPaddingPhone: CGFloat = 90
        static let bottomStackViewPaddingPad: CGFloat = 32
        static let bottomStackViewPaddingPhone: CGFloat = 0
        static let horizontalTopStackViewPaddingPad: CGFloat = 100
        static let horizontalTopStackViewPaddingPhone: CGFloat = 24
        static let scrollViewVerticalPadding: CGFloat = 62
        static let buttonVerticalInset: CGFloat = 12
        static let buttonHorizontalInset: CGFloat = 16
        static let buttonFontSize: CGFloat = 16
        static let titleFontSize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 28 : 22
        static let descriptionBoldFontSize: CGFloat = 20
        static let descriptionFontSize: CGFloat = 17
        static let imageViewSize = CGSize(width: 240, height: 300)

        // small device
        static let smallTitleFontSize: CGFloat = 20
        static let smallStackViewSpacing: CGFloat = 8
        static let smallScrollViewVerticalPadding: CGFloat = 20
        static let smallImageViewSize = CGSize(width: 240, height: 300)
        static let smallTopStackViewPadding: CGFloat = 40

        // tiny device (SE 1st gen)
        static let tinyImageViewSize = CGSize(width: 144, height: 180)
    }

    // MARK: - Properties
    var viewModel: OnboardingCardProtocol
    weak var delegate: OnboardingCardDelegate?
    var notificationCenter: NotificationProtocol
    var themeManager: ThemeManager
    var themeObserver: NSObjectProtocol?

    // Adjusting layout for devices with height lower than 667
    // including now iPhone SE 2nd generation and iPad
    var shouldUseSmallDeviceLayout: Bool {
        return view.frame.height <= 667 || UIDevice.current.userInterfaceIdiom == .pad
    }

    // Adjusting layout for tiny devices (iPhone SE 1st generation)
    var shouldUseTinyDeviceLayout: Bool {
        return UIDevice().isTinyFormFactor
    }

    private lazy var scrollView: UIScrollView = .build { view in
        view.backgroundColor = .clear
    }

    lazy var containerView: UIView = .build { view in
        view.backgroundColor = .clear
    }

    lazy var contentContainerView: UIView = .build { stack in
        stack.backgroundColor = .clear
    }

    lazy var topStackView: UIStackView = .build { stack in
        stack.backgroundColor = .clear
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = UX.topStackViewSpacing
        stack.axis = .vertical
    }

    lazy var contentStackView: UIStackView = .build { stack in
        stack.backgroundColor = .clear
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.spacing = UX.stackViewSpacing
        stack.axis = .vertical
    }

    lazy var imageView: UIImageView = .build { imageView in
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIdentifier = "\(self.viewModel.infoModel.a11yIdRoot)ImageView"
    }

    private lazy var titleLabel: UILabel = .build { label in
        label.numberOfLines = 0
        label.textAlignment = .center
        let fontSize = self.shouldUseSmallDeviceLayout ? UX.smallTitleFontSize : UX.titleFontSize
        label.font = DynamicFontHelper.defaultHelper.preferredBoldFont(withTextStyle: .largeTitle,
                                                                       size: fontSize)
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityIdentifier = "\(self.viewModel.infoModel.a11yIdRoot)TitleLabel"
    }

    // Only available for Welcome card and default cases
    private lazy var descriptionBoldLabel: UILabel = .build { label in
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = DynamicFontHelper.defaultHelper.preferredBoldFont(withTextStyle: .title3,
                                                                       size: UX.descriptionBoldFontSize)
        label.isHidden = true
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityIdentifier = "\(self.viewModel.infoModel.a11yIdRoot)DescriptionBoldLabel"
    }

    private lazy var descriptionLabel: UILabel = .build { label in
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = DynamicFontHelper.defaultHelper.preferredFont(withTextStyle: .body,
                                                                   size: UX.descriptionFontSize)
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityIdentifier = "\(self.viewModel.infoModel.a11yIdRoot)DescriptionLabel"
    }

    lazy var buttonStackView: UIStackView = .build { stack in
        stack.backgroundColor = .clear
        stack.distribution = .equalSpacing
        stack.spacing = UX.stackViewSpacing
        stack.axis = .vertical
    }

    private lazy var primaryButton: ResizableButton = .build { button in
        button.titleLabel?.font = DynamicFontHelper.defaultHelper.preferredBoldFont(
            withTextStyle: .callout,
            size: UX.buttonFontSize)
        button.layer.cornerRadius = UX.buttonCornerRadius
        button.titleLabel?.textAlignment = .center
        button.addTarget(self, action: #selector(self.primaryAction), for: .touchUpInside)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = "\(self.viewModel.infoModel.a11yIdRoot)PrimaryButton"
        button.contentEdgeInsets = UIEdgeInsets(top: UX.buttonVerticalInset,
                                                left: UX.buttonHorizontalInset,
                                                bottom: UX.buttonVerticalInset,
                                                right: UX.buttonHorizontalInset)
    }

    private lazy var secondaryButton: ResizableButton = .build { button in
        button.titleLabel?.font = DynamicFontHelper.defaultHelper.preferredBoldFont(
            withTextStyle: .callout,
            size: UX.buttonFontSize)
        button.layer.cornerRadius = UX.buttonCornerRadius
        button.titleLabel?.textAlignment = .center
        button.addTarget(self, action: #selector(self.secondaryAction), for: .touchUpInside)
        button.accessibilityIdentifier = "\(self.viewModel.infoModel.a11yIdRoot)SecondaryButton"
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.contentEdgeInsets = UIEdgeInsets(top: UX.buttonVerticalInset,
                                                left: UX.buttonHorizontalInset,
                                                bottom: UX.buttonVerticalInset,
                                                right: UX.buttonHorizontalInset)
    }

    private lazy var linkButton: ResizableButton = .build { button in
        button.titleLabel?.font = DynamicFontHelper.defaultHelper.preferredFont(withTextStyle: .subheadline, size: UX.buttonFontSize)
        button.titleLabel?.textAlignment = .center
        button.addTarget(self, action: #selector(self.linkButtonAction), for: .touchUpInside)
        button.setTitleColor(.systemBlue, for: .normal)
        button.backgroundColor = .clear
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.contentEdgeInsets = UIEdgeInsets(top: UX.buttonVerticalInset,
                                                left: UX.buttonHorizontalInset,
                                                bottom: UX.buttonVerticalInset,
                                                right: UX.buttonHorizontalInset)
    }

    private var imageViewHeight: CGFloat {
        if shouldUseTinyDeviceLayout {
            return UX.tinyImageViewSize.height
        } else if shouldUseSmallDeviceLayout {
            return UX.imageViewSize.height
        } else {
            return UX.smallImageViewSize.height
        }
    }

    // MARK: - Initializers
    init(viewModel: OnboardingCardProtocol,
         delegate: OnboardingCardDelegate?,
         themeManager: ThemeManager = AppContainer.shared.resolve(),
         notificationCenter: NotificationProtocol = NotificationCenter.default) {
        self.viewModel = viewModel
        self.delegate = delegate
        self.themeManager = themeManager
        self.notificationCenter = notificationCenter

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        listenForThemeChange(view)
        setupView()
        updateLayout()
        applyTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        delegate?.pageChanged(viewModel.cardType)
        viewModel.sendCardViewTelemetry()
    }

    // MARK: - View setup
    func setupView() {
        view.backgroundColor = .clear

        addViewsToView()

        // Adapt layout for smaller screens
        var scrollViewVerticalPadding = UX.scrollViewVerticalPadding
        var topPadding = UX.topStackViewPaddingPhone
        var horizontalTopStackViewPadding = UX.horizontalTopStackViewPaddingPhone
        var bottomStackViewPadding = UX.bottomStackViewPaddingPhone

        if UIDevice.current.userInterfaceIdiom == .pad {
            topStackView.spacing = UX.stackViewSpacing
            buttonStackView.spacing = UX.stackViewSpacingButtons
            if traitCollection.horizontalSizeClass == .regular {
                scrollViewVerticalPadding = UX.smallScrollViewVerticalPadding
                topPadding = UX.topStackViewPaddingPad
                horizontalTopStackViewPadding = UX.horizontalTopStackViewPaddingPad
                bottomStackViewPadding = -UX.bottomStackViewPaddingPad
            } else {
                scrollViewVerticalPadding = UX.smallScrollViewVerticalPadding
                topPadding = UX.topStackViewPaddingPhone
                horizontalTopStackViewPadding = UX.horizontalTopStackViewPaddingPhone
                bottomStackViewPadding = -UX.bottomStackViewPaddingPhone
            }
        } else if UIDevice.current.userInterfaceIdiom == .phone {
            horizontalTopStackViewPadding = UX.horizontalTopStackViewPaddingPhone
            bottomStackViewPadding = -UX.bottomStackViewPaddingPhone
            if shouldUseSmallDeviceLayout {
                topStackView.spacing = UX.smallStackViewSpacing
                buttonStackView.spacing = UX.smallStackViewSpacing
                scrollViewVerticalPadding = UX.smallScrollViewVerticalPadding
                topPadding = UX.smallTopStackViewPadding
            } else {
                topStackView.spacing = UX.stackViewSpacing
                buttonStackView.spacing = UX.stackViewSpacingButtons
                scrollViewVerticalPadding = UX.scrollViewVerticalPadding
                topPadding = UX.topStackViewPaddingPhone
            }
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: scrollViewVerticalPadding),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -scrollViewVerticalPadding),

            scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: view.topAnchor, constant: scrollViewVerticalPadding),
            scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -scrollViewVerticalPadding),
            scrollView.frameLayoutGuide.heightAnchor.constraint(equalTo: containerView.heightAnchor).priority(.defaultLow),

            scrollView.contentLayoutGuide.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.contentLayoutGuide.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.contentLayoutGuide.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.contentLayoutGuide.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            // Content view wrapper around text
            contentContainerView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: topPadding),
            contentContainerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: bottomStackViewPadding),
            contentContainerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            contentStackView.topAnchor.constraint(greaterThanOrEqualTo: contentContainerView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: horizontalTopStackViewPadding),
            contentStackView.bottomAnchor.constraint(greaterThanOrEqualTo: contentContainerView.bottomAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -horizontalTopStackViewPadding),
            contentStackView.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor),

            topStackView.topAnchor.constraint(equalTo: contentStackView.topAnchor),
            topStackView.leadingAnchor.constraint(equalTo: contentStackView.leadingAnchor),
            topStackView.trailingAnchor.constraint(equalTo: contentStackView.trailingAnchor),

            linkButton.leadingAnchor.constraint(equalTo: contentStackView.leadingAnchor),
            linkButton.trailingAnchor.constraint(equalTo: contentStackView.trailingAnchor),

            buttonStackView.leadingAnchor.constraint(equalTo: contentStackView.leadingAnchor),
            buttonStackView.bottomAnchor.constraint(equalTo: contentStackView.bottomAnchor),
            buttonStackView.trailingAnchor.constraint(equalTo: contentStackView.trailingAnchor),

            imageView.heightAnchor.constraint(equalToConstant: imageViewHeight)
        ])
    }

    private func addViewsToView() {
        topStackView.addArrangedSubview(imageView)
        topStackView.addArrangedSubview(titleLabel)
        topStackView.addArrangedSubview(descriptionBoldLabel)
        topStackView.addArrangedSubview(descriptionLabel)
        contentStackView.addArrangedSubview(topStackView)
        contentStackView.addArrangedSubview(linkButton)

        buttonStackView.addArrangedSubview(primaryButton)
        buttonStackView.addArrangedSubview(secondaryButton)
        contentStackView.addArrangedSubview(buttonStackView)

        contentContainerView.addSubview(contentStackView)
        containerView.addSubviews(contentContainerView)
        scrollView.addSubviews(containerView)
        view.addSubview(scrollView)
    }

    private func updateLayout() {
        titleLabel.text = viewModel.infoModel.title
        descriptionBoldLabel.isHidden = !viewModel.shouldShowDescriptionBold
        descriptionBoldLabel.text = .Onboarding.Intro.DescriptionPart1
        descriptionLabel.text = viewModel.infoModel.body

        imageView.image = viewModel.infoModel.image
        primaryButton.setTitle(viewModel.infoModel.buttons.primary.title,
                               for: .normal)
        handleSecondaryButton()
    }

    private func handleSecondaryButton() {
        // To keep Title, Description aligned between cards we don't hide the button
        // we clear the background and make disabled
        guard let buttonTitle = viewModel.infoModel.buttons.secondary?.title else {
            secondaryButton.isUserInteractionEnabled = false
            secondaryButton.backgroundColor = .clear
            return
        }

        secondaryButton.setTitle(buttonTitle, for: .normal)
    }

    private func handleLinkButton() {
        guard let buttonTitle = viewModel.infoModel.link?.title else {
            linkButton.isUserInteractionEnabled = false
            linkButton.isHidden = true
            return
        }
        linkButton.setTitle(buttonTitle, for: .normal)
    }

    // MARK: - Button Actions
    @objc
    func primaryAction() {
        viewModel.sendTelemetryButton(isPrimaryAction: true)
        delegate?.handleButtonPress(
            for: viewModel.infoModel.buttons.primary.action,
            from: viewModel.cardType)
    }

    @objc
    func secondaryAction() {
        guard let buttonAction = viewModel.infoModel.buttons.secondary?.action else { return }

        viewModel.sendTelemetryButton(isPrimaryAction: false)
        delegate?.handleButtonPress(
            for: buttonAction,
            from: viewModel.cardType)
    }

    @objc
    func linkButtonAction() {
        delegate?.handleButtonPress(for: .readPrivacyPolicy, from: viewModel.cardType)
    }

    // MARK: - Themeable
    func applyTheme() {
        let theme = themeManager.currentTheme
        titleLabel.textColor = theme.colors.textPrimary
        descriptionLabel.textColor  = theme.colors.textPrimary
        descriptionBoldLabel.textColor = theme.colors.textPrimary

        primaryButton.setTitleColor(theme.colors.textInverted, for: .normal)
        primaryButton.backgroundColor = theme.colors.actionPrimary

        secondaryButton.setTitleColor(theme.colors.textSecondaryAction, for: .normal)
        secondaryButton.backgroundColor = theme.colors.actionSecondary
        handleSecondaryButton()
        handleLinkButton()
    }
}
