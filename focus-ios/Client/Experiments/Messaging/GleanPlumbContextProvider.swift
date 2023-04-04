// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Common
import Shared
import Storage

class GleanPlumbContextProvider {
    enum ContextKey: String {
        case todayDate = "date_string"
        case isDefaultBrowser = "is_default_browser"
        case isInactiveNewUser = "is_inactive_new_user"
        case allowedTipsNotifications = "allowed_tips_notifications"
    }

    struct Constant {
        #if MOZ_CHANNEL_FENNEC
        // shorter time interval for development
        static let activityReferencePeriod: UInt64 = UInt64(60 * 2 * 1000) // 2 minutes in milliseconds
        static let inactivityPeriod: UInt64 = activityReferencePeriod / 2 // 1 minutes in milliseconds
        #else
        static let activityReferencePeriod: UInt64 = UInt64(60 * 60 * 48 * 1000) // 48 hours in milliseconds
        static let inactivityPeriod: UInt64 = UInt64(60 * 60 * 24 * 1000) // 24 hours in milliseconds
        #endif
    }

    var userDefaults: UserDefaultsInterface = UserDefaults.standard

    private var todaysDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-mm-dd"
        return dateFormatter.string(from: Date())
    }

    private var isDefaultBrowser: Bool {
        return userDefaults.bool(forKey: RatingPromptManager.UserDefaultsKey.keyIsBrowserDefault.rawValue)
    }

    var isInactiveNewUser: Bool {
        // existing users don't have firstAppUse set
        guard let firstAppUse = userDefaults.object(forKey: PrefsKeys.KeyFirstAppUse) as? UInt64
        else { return false }

        let now = Date()
        let notificationDate = Date.fromTimestamp(firstAppUse + Constant.activityReferencePeriod)

        // check that we are not past the reference time for inactive user check
        guard now < notificationDate else { return false }

        // We don't care how often the user is active in the first 24 hours after first use.
        // If they are not active in the second 24 hours after first use they are considered inactive.
        return now < Date.fromTimestamp(firstAppUse + Constant.inactivityPeriod)
    }

    private var allowedTipsNotifications: Bool {
        let featureEnabled = FxNimbus.shared.features.notificationSettingsFeature.value().notificationSettingsFeatureStatus
        let userPreference = userDefaults.bool(forKey: PrefsKeys.Notifications.TipsAndFeaturesNotifications)
        return featureEnabled && userPreference
    }

    /// JEXLs are more accurately evaluated when given certain details about the app on device.
    /// There is a limited amount of context you can give. See:
    /// - https://experimenter.info/mobile-messaging/#list-of-attributes
    /// We should pass as much device context as possible.
    func createAdditionalDeviceContext() -> [String: Any] {
        return [ContextKey.todayDate.rawValue: todaysDate,
                ContextKey.isDefaultBrowser.rawValue: isDefaultBrowser,
                ContextKey.isInactiveNewUser.rawValue: isInactiveNewUser,
                ContextKey.allowedTipsNotifications.rawValue: allowedTipsNotifications]
    }
}
