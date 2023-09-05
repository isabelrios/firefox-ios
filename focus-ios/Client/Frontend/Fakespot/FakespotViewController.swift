// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import ComponentLibrary
import UIKit
import Shared

class FakespotViewController: UIViewController, Themeable, UIAdaptivePresentationControllerDelegate {
    private struct UX {
        static let closeButtonWidthHeight: CGFloat = 30
        static let topLeadingTrailingSpacing: CGFloat = 18
        static let logoSize: CGFloat = 36
        static let titleLabelFontSize: CGFloat = 17
        static let headerSpacing = 8.0
        static let headerBottomMargin = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        static let topPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 40
        static let horizontalPadding: CGFloat = 16
        static let stackSpacing: CGFloat = 16
    }

    var notificationCenter: NotificationProtocol
    var themeManager: ThemeManager
    var themeObserver: NSObjectProtocol?
    private let viewModel: FakespotViewModel
    weak var delegate: FakespotViewControllerDelegate?

    private lazy var scrollView: UIScrollView = .build()

    private lazy var contentStackView: UIStackView = .build { stackView in
        stackView.axis = .vertical
        stackView.spacing = UX.stackSpacing
    }

    private lazy var headerStackView: UIStackView = .build { stackView in
        stackView.alignment = .center
        stackView.spacing = UX.headerSpacing
        stackView.layoutMargins = UX.headerBottomMargin
        stackView.isLayoutMarginsRelativeArrangement = true
    }

    private lazy var logoImageView: UIImageView = .build { imageView in
        imageView.image = UIImage(named: ImageIdentifiers.homeHeaderLogoBall)
        imageView.contentMode = .scaleAspectFit
    }

    private lazy var titleLabel: UILabel = .build { label in
        label.text = .Shopping.SheetHeaderTitle
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.font = DefaultDynamicFontHelper.preferredFont(withTextStyle: .headline,
                                                            size: UX.titleLabelFontSize,
                                                            weight: .semibold)
        label.accessibilityIdentifier = AccessibilityIdentifiers.Shopping.sheetHeaderTitle
    }

    private lazy var closeButton: UIButton = .build { button in
        button.setImage(UIImage(named: StandardImageIdentifiers.ExtraLarge.crossCircleFill), for: .normal)
        button.addTarget(self, action: #selector(self.closeTapped), for: .touchUpInside)
        button.accessibilityLabel = .CloseButtonTitle
    }

    private lazy var errorCardView: FakespotErrorCardView = .build()
    private lazy var reliabilityCardView: ReliabilityCardView = .build()
    private lazy var highlightsCardView: HighlightsCardView = .build()
    private lazy var settingsCardView: FakespotSettingsCardView = .build()
    private lazy var loadingView: FakespotLoadingView = .build()
    private lazy var noAnalysisCardView: NoAnalysisCardView = .build()
    private lazy var adjustRatingView: AdjustRatingView = .build()

    // MARK: - Initializers
    init(
        viewModel: FakespotViewModel,
        notificationCenter: NotificationProtocol = NotificationCenter.default,
        themeManager: ThemeManager = AppContainer.shared.resolve()
    ) {
        self.viewModel = viewModel
        self.notificationCenter = notificationCenter
        self.themeManager = themeManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View setup & lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        presentationController?.delegate = self
        setupView()
        listenForThemeChange(view)

        reliabilityCardView.configure(viewModel.reliabilityCardViewModel)
        errorCardView.configure(viewModel.errorCardViewModel)
        highlightsCardView.configure(viewModel.highlightsCardViewModel)
        settingsCardView.configure(viewModel.settingsCardViewModel)
        adjustRatingView.configure(viewModel.adjustRatingViewModel)
        noAnalysisCardView.configure(viewModel.noAnalysisCardViewModel)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        applyTheme()
        loadingView.animate()
        Task {
            await viewModel.fetchData()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentingViewController == nil {
            recordTelemetry()
        }
    }

    func applyTheme() {
        let theme = themeManager.currentTheme

        view.backgroundColor = theme.colors.layer1
        titleLabel.textColor = theme.colors.textPrimary

        errorCardView.applyTheme(theme: theme)
        reliabilityCardView.applyTheme(theme: theme)
        highlightsCardView.applyTheme(theme: theme)
        settingsCardView.applyTheme(theme: theme)
        noAnalysisCardView.applyTheme(theme: theme)
        loadingView.applyTheme(theme: theme)
        adjustRatingView.applyTheme(theme: themeManager.currentTheme)
    }

    private func setupView() {
        view.addSubviews(headerStackView, scrollView, closeButton)
        contentStackView.addArrangedSubview(reliabilityCardView)
        contentStackView.addArrangedSubview(adjustRatingView)
        contentStackView.addArrangedSubview(highlightsCardView)
        contentStackView.addArrangedSubview(errorCardView)
        contentStackView.addArrangedSubview(settingsCardView)
        contentStackView.addArrangedSubview(noAnalysisCardView)
        contentStackView.addArrangedSubview(loadingView)
        scrollView.addSubview(contentStackView)
        [logoImageView, titleLabel].forEach(headerStackView.addArrangedSubview)

        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor,
                                                  constant: UX.topPadding),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                                                      constant: UX.horizontalPadding),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                                                     constant: -UX.bottomPadding),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                                                       constant: -UX.horizontalPadding),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor,
                                                    constant: -UX.horizontalPadding * 2),

            scrollView.topAnchor.constraint(equalTo: headerStackView.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            headerStackView.topAnchor.constraint(equalTo: view.topAnchor,
                                                 constant: UX.topLeadingTrailingSpacing),
            headerStackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                                                     constant: UX.topLeadingTrailingSpacing),
            headerStackView.trailingAnchor.constraint(equalTo: closeButton.safeAreaLayoutGuide.leadingAnchor),

            logoImageView.widthAnchor.constraint(equalToConstant: UX.logoSize),
            logoImageView.heightAnchor.constraint(equalToConstant: UX.logoSize),

            closeButton.topAnchor.constraint(equalTo: view.topAnchor,
                                             constant: UX.topLeadingTrailingSpacing),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                                                  constant: -UX.topLeadingTrailingSpacing),
            closeButton.widthAnchor.constraint(equalToConstant: UX.closeButtonWidthHeight),
            closeButton.heightAnchor.constraint(equalToConstant: UX.closeButtonWidthHeight)
        ])
    }

    private func recordTelemetry() {
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .close,
                                     object: .shoppingBottomSheet)
    }

    @objc
    private func closeTapped() {
        delegate?.fakespotControllerDidDismiss()
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        delegate?.fakespotControllerDidDismiss()
    }
}
