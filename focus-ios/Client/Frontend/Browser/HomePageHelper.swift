/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import XCGLogger

private let log = Logger.browserLogger

struct HomePageConstants {
    static let HomePageURLPrefKey = "HomePageURLPref"
    static let DefaultHomePageURLPrefKey = PrefsKeys.KeyDefaultHomePageURL
    static let HomePageButtonIsInMenuPrefKey = PrefsKeys.KeyHomePageButtonIsInMenu
}

class HomePageHelper {

    let prefs: Prefs

    var currentURL: NSURL? {
        get {
            return HomePageAccessors.getHomePage(prefs)
        }
        set {
            if let url = newValue {
                prefs.setString(url.absoluteString, forKey: HomePageConstants.HomePageURLPrefKey)
            } else {
                prefs.removeObjectForKey(HomePageConstants.HomePageURLPrefKey)
            }
        }
    }

    var defaultURLString: String? {
        return HomePageAccessors.getDefaultHomePageString(prefs)
    }

    var isHomePageAvailable: Bool { return currentURL != nil }

    init(prefs: Prefs) {
        self.prefs = prefs
    }

    func openHomePage(tab: Tab) {
        guard let url = currentURL else {
            // this should probably never happen.
            log.error("User requested a homepage that wasn't a valid URL")
            return
        }
        tab.loadRequest(NSURLRequest(URL: url))
    }

    func openHomePage(inTab tab: Tab, withNavigationController navigationController: UINavigationController?) {
        if isHomePageAvailable {
            openHomePage(tab)
        } else {
            setHomePage(toTab: tab, withNavigationController: navigationController)
        }
    }

    func setHomePage(toTab tab: Tab, withNavigationController navigationController: UINavigationController?) {
        let alertController = UIAlertController(
            title: Strings.SetHomePageDialogTitle,
            message: Strings.SetHomePageDialogMessage,
            preferredStyle: UIAlertControllerStyle.Alert)
        alertController.addAction(UIAlertAction(title: Strings.SetHomePageDialogNo, style: .Cancel, handler: nil))
        alertController.addAction(UIAlertAction(title: Strings.SetHomePageDialogYes, style: .Default) { _ in
            self.currentURL = tab.url
            })
        navigationController?.presentViewController(alertController, animated: true, completion: nil)
    }
}

/// Accessors for homepage details from the app state.
/// These are pure functions, so it's quite ok to have them 
/// as static.
class HomePageAccessors {
    private static let getPrefs = Accessors.getPrefs

    static func getHomePage(state: AppState) -> NSURL? {
        return getHomePage(getPrefs(state))
    }

    static func hasHomePage(state: AppState) -> Bool {
        return getHomePage(state) != nil
    }

    static func isButtonInMenu(state: AppState) -> Bool {
        return isButtonInMenu(getPrefs(state))
    }

    static func isButtonEnabled(state: AppState) -> Bool {
        switch state.ui {
        case .Tab:
            return true
        case .HomePanels, .Loading:
            return hasHomePage(state)
        default:
            return false
        }
    }
}

private extension HomePageAccessors {
    static func isButtonInMenu(prefs: Prefs) -> Bool {
        return prefs.boolForKey(HomePageConstants.HomePageButtonIsInMenuPrefKey) ?? true
    }

    static func getHomePage(prefs: Prefs) -> NSURL? {
        let string = prefs.stringForKey(HomePageConstants.HomePageURLPrefKey) ?? getDefaultHomePageString(prefs)
        guard let urlString = string else {
            return nil
        }
        return NSURL(string: urlString)
    }

    static func getDefaultHomePageString(prefs: Prefs) -> String? {
        return prefs.stringForKey(HomePageConstants.DefaultHomePageURLPrefKey)
    }
}