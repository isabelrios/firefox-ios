/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import Shared
import SwiftKeychainWrapper


class TurnPasscodeOnSetting: Setting {
    let prefs: Prefs

    init(settings: SettingsTableViewController, delegate: SettingsDelegate? = nil) {
        self.prefs = settings.profile.prefs
        super.init(title: NSAttributedString.tableRowTitle(AuthenticationStrings.turnOnPasscode),
                   delegate: delegate)
    }

    override func onClick(navigationController: UINavigationController?) {
        // Navigate to passcode configuration screen
        let passcodeVC = PasscodeConfirmViewController.newPasscodeVC(prefs: self.prefs)
        passcodeVC.title = AuthenticationStrings.setPasscode
        let passcodeNav = UINavigationController(rootViewController: passcodeVC)
        navigationController?.presentViewController(passcodeNav, animated: true, completion: nil)
    }
}

class TurnPasscodeOffSetting: Setting {
    let prefs: Prefs

    init(settings: SettingsTableViewController, delegate: SettingsDelegate? = nil) {
        self.prefs = settings.profile.prefs
        super.init(title: NSAttributedString.tableRowTitle(AuthenticationStrings.turnOffPasscode),
                   delegate: delegate)
    }

    override func onClick(navigationController: UINavigationController?) {
        let passcodeVC = PasscodeConfirmViewController.removePasscodeVC(prefs: self.prefs)
        passcodeVC.title = AuthenticationStrings.turnOffPasscode
        let passcodeNav = UINavigationController(rootViewController: passcodeVC)
        navigationController?.presentViewController(passcodeNav, animated: true, completion: nil)
    }
}

class ChangePasscodeSetting: Setting {
    let prefs: Prefs

    init(settings: SettingsTableViewController, delegate: SettingsDelegate? = nil, enabled: Bool) {
        self.prefs = settings.profile.prefs
        let attributedTitle: NSAttributedString = (enabled ?? false) ?
            NSAttributedString.tableRowTitle(AuthenticationStrings.changePasscode) :
            NSAttributedString.disabledTableRowTitle(AuthenticationStrings.changePasscode)

        super.init(title: attributedTitle,
                   delegate: delegate,
                   enabled: enabled)
    }

    override func onClick(navigationController: UINavigationController?) {
        let passcodeVC = PasscodeConfirmViewController.changePasscodeVC(prefs: self.prefs)
        passcodeVC.title = AuthenticationStrings.changePasscode
        let passcodeNav = UINavigationController(rootViewController: passcodeVC)
        navigationController?.presentViewController(passcodeNav, animated: true, completion: nil)
    }
}

class RequirePasscodeSetting: Setting {
    let prefs: Prefs

    override var accessoryType: UITableViewCellAccessoryType { return .DisclosureIndicator }

    override var style: UITableViewCellStyle { return .Value1 }

    override var status: NSAttributedString {
        // Only show the interval if we are enabled and have an interval set.
        if let interval = prefs.intForKey(PrefKeyRequirePasscodeInterval),
           let valueType = PasscodeInterval(rawValue: interval)
           where enabled
        {
            return NSAttributedString.disabledTableRowTitle(valueType.settingTitle)
        }
        return NSAttributedString(string: "")
    }

    init(settings: SettingsTableViewController, delegate: SettingsDelegate? = nil, enabled: Bool? = nil) {
        self.prefs = settings.profile.prefs
        let title = AuthenticationStrings.requirePasscode
        let attributedTitle = (enabled ?? true) ? NSAttributedString.tableRowTitle(title) : NSAttributedString.disabledTableRowTitle(title)
        super.init(title: attributedTitle,
                   delegate: delegate,
                   enabled: enabled)
    }

    override func onClick(navigationController: UINavigationController?) {
        navigationController?.pushViewController(RequirePasscodeIntervalViewController(prefs: self.prefs), animated: true)
    }
}

class AuthenticationSettingsViewController: SettingsTableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = NSLocalizedString("Touch ID & Passcode", tableName: "AuthenticationManager", comment: "Title for Touch ID/Passcode settings option")

        let notificationCenter = NSNotificationCenter.defaultCenter()
        notificationCenter.addObserver(self, selector: Selector("passcodeStateChanged:"), name: NotificationPasscodeDidRemove, object: nil)
        notificationCenter.addObserver(self, selector: Selector("passcodeStateChanged:"), name: NotificationPasscodeDidCreate, object: nil)

        tableView.accessibilityIdentifier = "AuthenticationManager.settingsTableView"
    }

    deinit {
        let notificationCenter = NSNotificationCenter.defaultCenter()
        notificationCenter.removeObserver(self, name: NotificationPasscodeDidRemove, object: nil)
        notificationCenter.removeObserver(self, name: NotificationPasscodeDidCreate, object: nil)
    }

    override func generateSettings() -> [SettingSection] {
        if let _ = KeychainWrapper.stringForKey(KeychainKeyPasscode) {
            return passcodeEnabledSettings()
        } else {
            return passcodeDisabledSettings()
        }
    }

    private func passcodeEnabledSettings() -> [SettingSection] {
        var settings = [SettingSection]()

        let passcodeSectionTitle = NSAttributedString(string: NSLocalizedString("Passcode", tableName: "AuthenticationManager", comment: "List section title for passcode settings"))
        let passcodeSection = SettingSection(title: passcodeSectionTitle, children: [
            TurnPasscodeOffSetting(settings: self),
            ChangePasscodeSetting(settings: self, delegate: nil, enabled: true)
        ])

        let prefs = profile.prefs
        let requirePasscodeSection = SettingSection(title: nil, children: [
            RequirePasscodeSetting(settings: self),
            BoolSetting(prefs: prefs,
                prefKey: "touchid.logins",
                defaultValue: false,
                titleText: NSLocalizedString("Use Touch ID", tableName:  "AuthenticationManager", comment: "List section title for when to use Touch ID")
            ),
        ])

        settings += [
            passcodeSection,
            requirePasscodeSection,
        ]

        return settings
    }

    private func passcodeDisabledSettings() -> [SettingSection] {
        var settings = [SettingSection]()

        let passcodeSectionTitle = NSAttributedString(string: NSLocalizedString("Passcode", tableName: "AuthenticationManager", comment: "List section title for passcode settings"))
        let passcodeSection = SettingSection(title: passcodeSectionTitle, children: [
            TurnPasscodeOnSetting(settings: self),
            ChangePasscodeSetting(settings: self, delegate: nil, enabled: false)
        ])

        let requirePasscodeSection = SettingSection(title: nil, children: [
            RequirePasscodeSetting(settings: self, delegate: nil, enabled: false),
        ])

        settings += [
            passcodeSection,
            requirePasscodeSection,
        ]

        return settings
    }
}

extension AuthenticationSettingsViewController {
    func passcodeStateChanged(notification: NSNotification) {
        generateSettings()
        tableView.reloadData()
    }
}