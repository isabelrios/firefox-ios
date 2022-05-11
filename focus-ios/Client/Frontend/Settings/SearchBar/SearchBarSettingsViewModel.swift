// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared

enum SearchBarPosition: String {
    case bottom
    case top

    var getLocalizedTitle: String {
        switch self {
        case .bottom:
            return .Settings.Toolbar.Bottom
        case .top:
            return .Settings.Toolbar.Top
        }
    }
}

protocol SearchBarPreferenceDelegate: AnyObject {
    func didUpdateSearchBarPositionPreference()
}

final class SearchBarSettingsViewModel {

    static var isEnabled: Bool {
        let isiPad = UIDevice.current.userInterfaceIdiom == .pad
        let isFeatureEnabled = FeatureFlagsManager.shared.isFeatureEnabled(.bottomSearchBar, checking: .buildOnly)
        return !isiPad && isFeatureEnabled && !AppConstants.IsRunningTest
    }

    var title: String = .Settings.Toolbar.Toolbar
    weak var delegate: SearchBarPreferenceDelegate?

    private let prefs: Prefs
    init(prefs: Prefs) {
        self.prefs = prefs
    }

    var searchBarTitle: String {
        searchBarPosition.getLocalizedTitle
    }

    var searchBarPosition: SearchBarPosition {
        guard let raw = prefs.stringForKey(PrefsKeys.KeySearchBarPosition) else {
            let defaultPosition = getDefaultSearchPosition()
            // Do not notify if it's the default position being saved
            saveSearchBarPosition(defaultPosition, shouldNotify: false)
            return defaultPosition
        }

        let position = SearchBarPosition(rawValue: raw) ?? .bottom
        return position
    }

    var topSetting: CheckmarkSetting {
        return CheckmarkSetting(title: NSAttributedString(string: SearchBarPosition.top.getLocalizedTitle),
                                subtitle: nil,
                                accessibilityIdentifier: AccessibilityIdentifiers.Settings.SearchBar.topSetting,
                                isChecked: { return self.searchBarPosition == .top },
                                onChecked: { self.saveSearchBarPosition(SearchBarPosition.top)}
        )
    }

    var bottomSetting: CheckmarkSetting {
        return CheckmarkSetting(title: NSAttributedString(string: SearchBarPosition.bottom.getLocalizedTitle),
                                subtitle: nil,
                                accessibilityIdentifier: AccessibilityIdentifiers.Settings.SearchBar.bottomSetting,
                                isChecked: { return self.searchBarPosition == .bottom },
                                onChecked: { self.saveSearchBarPosition(SearchBarPosition.bottom) }
        )
    }
}

// MARK: Private
private extension SearchBarSettingsViewModel {

    /// New user defaults to bottom search bar, existing users keep their existing search bar position
    func getDefaultSearchPosition() -> SearchBarPosition {
        return InstallType.get() == .fresh ? .bottom : .top
    }

    func saveSearchBarPosition(_ searchBarPosition: SearchBarPosition, shouldNotify: Bool = true) {
        prefs.setString(searchBarPosition.rawValue,
                        forKey: PrefsKeys.KeySearchBarPosition)
        delegate?.didUpdateSearchBarPositionPreference()
        recordPreferenceChange(searchBarPosition)

        guard shouldNotify else { return }
        let notificationObject = [PrefsKeys.KeySearchBarPosition: searchBarPosition]
        NotificationCenter.default.post(name: .SearchBarPositionDidChange, object: notificationObject)
    }

    func recordPreferenceChange(_ searchBarPosition: SearchBarPosition) {
        let extras = [TelemetryWrapper.EventExtraKey.preference.rawValue: PrefsKeys.KeySearchBarPosition,
                      TelemetryWrapper.EventExtraKey.preferenceChanged.rawValue: searchBarPosition.rawValue]
        TelemetryWrapper.recordEvent(category: .action, method: .change, object: .setting, extras: extras)
    }
}

// MARK: Telemetry
extension SearchBarSettingsViewModel {

    static func recordLocationTelemetry(for searchbarPosition: SearchBarPosition) {
        let extras = [TelemetryWrapper.EventExtraKey.preference.rawValue: searchbarPosition.rawValue]
        TelemetryWrapper.recordEvent(category: .information, method: .view, object: .awesomebarLocation, extras: extras)
    }
}
