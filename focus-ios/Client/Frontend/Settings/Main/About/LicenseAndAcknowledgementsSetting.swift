// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared

/// Opens the license page in a new tab
class LicenseAndAcknowledgementsSetting: Setting {
    override var title: NSAttributedString? {
        return NSAttributedString(string: .AppSettingsLicenses,
                                  attributes: [NSAttributedString.Key.foregroundColor: theme.colors.textPrimary])
    }

    override var url: URL? {
        return URL(string: "\(InternalURL.baseUrl)/\(AboutLicenseHandler.path)")
    }

    weak var settingsDelegate: AboutSettingsDelegate?

    init(settingsDelegate: AboutSettingsDelegate?) {
        self.settingsDelegate = settingsDelegate
    }

    override func onClick(_ navigationController: UINavigationController?) {
        if CoordinatorFlagManager.isSettingsCoordinatorEnabled {
            guard let url = self.url,
                  let title = self.title
            else { return }
            settingsDelegate?.pressedLicense(url: url, title: title)
            return
        }
        setUpAndPushSettingsContentViewController(navigationController, self.url)
    }
}
