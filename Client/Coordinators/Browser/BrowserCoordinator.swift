// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import WebKit
import Shared

class BrowserCoordinator: BaseCoordinator, LaunchCoordinatorDelegate, BrowserDelegate, SettingsCoordinatorDelegate, BrowserNavigationHandler, LibraryCoordinatorDelegate, EnhancedTrackingProtectionCoordinatorDelegate {
    var browserViewController: BrowserViewController
    var webviewController: WebviewViewController?
    var homepageViewController: HomepageViewController?

    private var profile: Profile
    private let tabManager: TabManager
    private let themeManager: ThemeManager
    private let screenshotService: ScreenshotService
    private let glean: GleanWrapper
    private let applicationHelper: ApplicationHelper
    private let wallpaperManager: WallpaperManagerInterface
    private let isSettingsCoordinatorEnabled: Bool
    private var browserIsReady = false

    init(router: Router,
         screenshotService: ScreenshotService,
         profile: Profile = AppContainer.shared.resolve(),
         tabManager: TabManager = AppContainer.shared.resolve(),
         themeManager: ThemeManager = AppContainer.shared.resolve(),
         glean: GleanWrapper = DefaultGleanWrapper.shared,
         applicationHelper: ApplicationHelper = DefaultApplicationHelper(),
         wallpaperManager: WallpaperManagerInterface = WallpaperManager(),
         isSettingsCoordinatorEnabled: Bool = CoordinatorFlagManager.isSettingsCoordinatorEnabled) {
        self.screenshotService = screenshotService
        self.profile = profile
        self.tabManager = tabManager
        self.themeManager = themeManager
        self.browserViewController = BrowserViewController(profile: profile, tabManager: tabManager)
        self.applicationHelper = applicationHelper
        self.glean = glean
        self.wallpaperManager = wallpaperManager
        self.isSettingsCoordinatorEnabled = isSettingsCoordinatorEnabled
        super.init(router: router)

        browserViewController.browserDelegate = self
        browserViewController.navigationHandler = self
    }

    func start(with launchType: LaunchType?) {
        router.push(browserViewController, animated: false)

        if let launchType = launchType, launchType.canLaunch(fromType: .BrowserCoordinator) {
            startLaunch(with: launchType)
        }
    }

    // MARK: - Helper methods

    private func startLaunch(with launchType: LaunchType) {
        let launchCoordinator = LaunchCoordinator(router: router)
        launchCoordinator.parentCoordinator = self
        add(child: launchCoordinator)
        launchCoordinator.start(with: launchType)
    }

    // MARK: - LaunchCoordinatorDelegate

    func didFinishLaunch(from coordinator: LaunchCoordinator) {
        router.dismiss(animated: true, completion: nil)
        remove(child: coordinator)

        // Once launch is done, we check for any saved Route
        if let savedRoute {
            findAndHandle(route: savedRoute)
        }
    }

    // MARK: - BrowserDelegate

    func showHomepage(inline: Bool,
                      homepanelDelegate: HomePanelDelegate,
                      libraryPanelDelegate: LibraryPanelDelegate,
                      sendToDeviceDelegate: HomepageViewController.SendToDeviceDelegate,
                      overlayManager: OverlayModeManager) {
        let homepageController = getHomepage(inline: inline,
                                             homepanelDelegate: homepanelDelegate,
                                             libraryPanelDelegate: libraryPanelDelegate,
                                             sendToDeviceDelegate: sendToDeviceDelegate,
                                             overlayManager: overlayManager)

        guard browserViewController.embedContent(homepageController) else { return }
        self.homepageViewController = homepageController
        homepageController.scrollToTop()
        // We currently don't support full page screenshot of the homepage
        screenshotService.screenshotableView = nil
    }

    func show(webView: WKWebView) {
        // Keep the webviewController in memory, update to newest webview when needed
        if let webviewController = webviewController {
            webviewController.update(webView: webView, isPrivate: tabManager.selectedTab?.isPrivate ?? false)
            browserViewController.frontEmbeddedContent(webviewController)
        } else {
            let webviewViewController = WebviewViewController(webView: webView, isPrivate: tabManager.selectedTab?.isPrivate ?? false)
            webviewController = webviewViewController
            _ = browserViewController.embedContent(webviewViewController)
        }

        screenshotService.screenshotableView = webviewController
    }

    func browserHasLoaded() {
        browserIsReady = true
        logger.log("Browser has loaded", level: .info, category: .coordinator)

        if let savedRoute {
            findAndHandle(route: savedRoute)
        }
    }

    private func getHomepage(inline: Bool,
                             homepanelDelegate: HomePanelDelegate,
                             libraryPanelDelegate: LibraryPanelDelegate,
                             sendToDeviceDelegate: HomepageViewController.SendToDeviceDelegate,
                             overlayManager: OverlayModeManager) -> HomepageViewController {
        if let homepageViewController = homepageViewController {
            return homepageViewController
        } else {
            let homepageViewController = HomepageViewController(
                profile: profile,
                isZeroSearch: inline,
                overlayManager: overlayManager
            )
            homepageViewController.homePanelDelegate = homepanelDelegate
            homepageViewController.libraryPanelDelegate = libraryPanelDelegate
            homepageViewController.sendToDeviceDelegate = sendToDeviceDelegate
            return homepageViewController
        }
    }

    // MARK: - Route handling

    override func handle(route: Route) -> Bool {
        guard browserIsReady else {
            logger.log("Could not handle route, wasn't ready", level: .info, category: .coordinator)
            return false
        }

        logger.log("Handling a route", level: .info, category: .coordinator)
        switch route {
        case let .searchQuery(query):
            handle(query: query)
            return true

        case let .search(url, isPrivate, options):
            handle(url: url, isPrivate: isPrivate, options: options)
            return true

        case let .searchURL(url, tabId):
            handle(searchURL: url, tabId: tabId)
            return true

        case let .glean(url):
            glean.handleDeeplinkUrl(url: url)
            return true

        case let .homepanel(section):
            handle(homepanelSection: section)
            return true

        case let .settings(section):
            // 'Else' case will be removed with FXIOS-6529
            if isSettingsCoordinatorEnabled {
                return handleSettings(with: section)
            } else {
                handle(settingsSection: section)
                return true
            }

        case let .action(routeAction):
            switch routeAction {
            case .closePrivateTabs:
                handleClosePrivateTabs()
                return true
            case .showQRCode:
                handleQRCode()
                return true
            case .showIntroOnboarding:
                return showIntroOnboarding()
            }

        case let .fxaSignIn(params):
            handle(fxaParams: params)
            return true

        case let .defaultBrowser(section):
            switch section {
            case .systemSettings:
                applicationHelper.openSettings()
            case .tutorial:
                startLaunch(with: .defaultBrowser)
            }
            return true
        }
    }

    private func showIntroOnboarding() -> Bool {
        let introManager = IntroScreenManager(prefs: profile.prefs)
        let launchType = LaunchType.intro(manager: introManager)
        startLaunch(with: launchType)
        return true
    }

    private func handleQRCode() {
        browserViewController.handleQRCode()
    }

    private func handleClosePrivateTabs() {
        browserViewController.handleClosePrivateTabs()
    }

    private func handle(homepanelSection section: Route.HomepanelSection) {
        switch section {
        case .bookmarks:
            browserViewController.showLibrary(panel: .bookmarks)
        case .history:
            browserViewController.showLibrary(panel: .history)
        case .readingList:
            browserViewController.showLibrary(panel: .readingList)
        case .downloads:
            browserViewController.showLibrary(panel: .downloads)
        case .topSites:
            browserViewController.openURLInNewTab(HomePanelType.topSites.internalUrl)
        case .newPrivateTab:
            browserViewController.openBlankNewTab(focusLocationField: false, isPrivate: true)
        case .newTab:
            browserViewController.openBlankNewTab(focusLocationField: false)
        }
    }

    private func handle(query: String) {
        browserViewController.handle(query: query)
    }

    private func handle(url: URL?, isPrivate: Bool, options: Set<Route.SearchOptions>? = nil) {
        browserViewController.handle(url: url, isPrivate: isPrivate, options: options)
    }

    private func handle(searchURL: URL?, tabId: String) {
        browserViewController.handle(url: searchURL, tabId: tabId)
    }

    private func handle(fxaParams: FxALaunchParams) {
        browserViewController.presentSignInViewController(fxaParams)
    }

    private func handleSettings(with section: Route.SettingsSection) -> Bool {
        guard !childCoordinators.contains(where: { $0 is SettingsCoordinator}) else {
            return false // route is handled with existing child coordinator
        }

        let navigationController = ThemedNavigationController()
        navigationController.modalPresentationStyle = .formSheet
        let settingsRouter = DefaultRouter(navigationController: navigationController)

        let settingsCoordinator = SettingsCoordinator(router: settingsRouter)
        settingsCoordinator.parentCoordinator = self
        add(child: settingsCoordinator)
        settingsCoordinator.start(with: section)

        router.present(navigationController) { [weak self] in
            self?.didFinishSettings(from: settingsCoordinator)
        }
        return true
    }

    private func showLibrary(with homepanelSection: Route.HomepanelSection) {
        if let libraryCoordinator = childCoordinators[LibraryCoordinator.self] {
            libraryCoordinator.start(with: homepanelSection)
            (libraryCoordinator.router.navigationController as? UINavigationController).map { router.present($0) }
        } else {
            let navigationController = DismissableNavigationViewController()
            navigationController.modalPresentationStyle = .formSheet

            let libraryCoordinator = LibraryCoordinator(
                router: DefaultRouter(navigationController: navigationController)
            )
            libraryCoordinator.parentCoordinator = self
            add(child: libraryCoordinator)
            libraryCoordinator.start(with: homepanelSection)

            router.present(navigationController)
        }
    }

    private func showETPMenu() {
        let navigationController = DismissableNavigationViewController()
        navigationController.modalPresentationStyle = .formSheet
        let etpRouter = DefaultRouter(navigationController: navigationController)
        let enhancedTrackingProtectionCoordinator = EnhancedTrackingProtectionCoordinator(router: etpRouter)
        enhancedTrackingProtectionCoordinator.parentCoordinator = self
        add(child: enhancedTrackingProtectionCoordinator)
        enhancedTrackingProtectionCoordinator.start()

        router.present(navigationController) { [weak self] in
            self?.didFinishEnhancedTrackingProtection(from: enhancedTrackingProtectionCoordinator)
        }
    }

    // MARK: - SettingsCoordinatorDelegate
    func openURLinNewTab(_ url: URL) {
        browserViewController.openURLInNewTab(url)
    }

    func didFinishSettings(from coordinator: SettingsCoordinator) {
        router.dismiss(animated: true, completion: nil)
        remove(child: coordinator)
    }

    // MARK: - LibraryCoordinatorDelegate

    func didFinishLibrary(from coordinator: LibraryCoordinator) {
        router.dismiss(animated: true, completion: nil)
        remove(child: coordinator)
    }
    // MARK: - EnhancedTrackingProtectionCoordinatorDelegate

    func didFinishEnhancedTrackingProtection(from coordinator: EnhancedTrackingProtectionCoordinator) {
        router.dismiss(animated: true, completion: nil)
        remove(child: coordinator)
    }

    // MARK: - BrowserNavigationHandler

    func show(settings: Route.SettingsSection) {
        _ = handleSettings(with: settings)
    }

    func show(homepanelSection: Route.HomepanelSection) {
        showLibrary(with: homepanelSection)
    }

    func showEnhancedTrackingProtection() {
        showETPMenu()
    }

    // MARK: - To be removed with FXIOS-6529
    private func handle(settingsSection: Route.SettingsSection) {
        // Temporary bugfix for #14954, real fix is with settings coordinator
        if let subNavigationController = router.navigationController.presentedViewController as? ThemedNavigationController,
           let settings = subNavigationController.viewControllers.first as? AppSettingsTableViewController {
            // Showing settings already, pass the deeplink down
            if let deeplinkTo = settingsSection.getSettingsRoute() {
                settings.deeplinkTo = deeplinkTo
                settings.checkForDeeplinkSetting()
            }
            return
        }

        let baseSettingsVC = AppSettingsTableViewController(
            with: profile,
            and: tabManager,
            delegate: browserViewController
        )

        let controller = ThemedNavigationController(rootViewController: baseSettingsVC)
        controller.presentingModalViewControllerDelegate = browserViewController
        controller.modalPresentationStyle = .formSheet
        router.present(controller)

        getSettingsViewController(settingsSection: settingsSection) { viewController in
            guard let viewController else { return }
            controller.pushViewController(viewController, animated: true)
        }
    }

    // Will be removed with FXIOS-6529
    func getSettingsViewController(settingsSection section: Route.SettingsSection,
                                   completion: @escaping (UIViewController?) -> Void) {
        switch section {
        case .newTab:
            let viewController = NewTabContentSettingsViewController(prefs: profile.prefs)
            viewController.profile = profile
            completion(viewController)

        case .homePage:
            let viewController = HomePageSettingViewController(prefs: profile.prefs)
            viewController.profile = profile
            completion(viewController)

        case .mailto:
            let viewController = OpenWithSettingsViewController(prefs: profile.prefs)
            completion(viewController)

        case .search:
            let viewController = SearchSettingsTableViewController(profile: profile)
            completion(viewController)

        case .clearPrivateData:
            let viewController = ClearPrivateDataTableViewController()
            viewController.profile = profile
            viewController.tabManager = tabManager
            completion(viewController)

        case .fxa:
            let fxaParams = FxALaunchParams(entrypoint: .fxaDeepLinkSetting, query: [:])
            let viewController = FirefoxAccountSignInViewController.getSignInOrFxASettingsVC(
                fxaParams,
                flowType: .emailLoginFlow,
                referringPage: .settings,
                profile: browserViewController.profile
            )
            completion(viewController)

        case .theme:
            completion(ThemeSettingsController())

        case .wallpaper:
            if wallpaperManager.canSettingsBeShown {
                let viewModel = WallpaperSettingsViewModel(
                    wallpaperManager: wallpaperManager,
                    tabManager: tabManager,
                    theme: themeManager.currentTheme
                )
                let wallpaperVC = WallpaperSettingsViewController(viewModel: viewModel)
                completion(wallpaperVC)
            } else {
                completion(nil)
            }

        case .creditCard:
            let viewModel = CreditCardSettingsViewModel(profile: profile)
            let viewController = CreditCardSettingsViewController(
                creditCardViewModel: viewModel)
            let appAuthenticator = AppAuthenticator()
            if appAuthenticator.canAuthenticateDeviceOwner {
                appAuthenticator.authenticateWithDeviceOwnerAuthentication { result in
                    switch result {
                    case .success:
                        completion(viewController)
                    case .failure:
                        break
                    }
                }
            } else {
                let passcodeViewController = DevicePasscodeRequiredViewController()
                passcodeViewController.profile = profile
                completion(passcodeViewController)
            }

        default:
            completion(nil)
        }
    }
}