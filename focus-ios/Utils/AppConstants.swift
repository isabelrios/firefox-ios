/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit

public enum AppBuildChannel {
    case Release
    case Beta
    case Nightly
    case Developer
    case Aurora
}

public struct AppConstants {
    public static let IsRunningTest = NSClassFromString("XCTestCase") != nil

    // True if this process is executed as part of a Fastlane Snapshot test
    public static let IsRunningFastlaneSnapshot = NSProcessInfo.processInfo().arguments.contains("FASTLANE_SNAPSHOT")

    /// Build Channel.
    public static let BuildChannel: AppBuildChannel = {
        #if MOZ_CHANNEL_RELEASE
            return AppBuildChannel.Release
        #elseif MOZ_CHANNEL_BETA
            return AppBuildChannel.Beta
        #elseif MOZ_CHANNEL_NIGHTLY
            return AppBuildChannel.Nightly
        #elseif MOZ_CHANNEL_FENNEC
            return AppBuildChannel.Developer
        #elseif MOZ_CHANNEL_AURORA
            return AppBuildChannel.Aurora
        #endif
    }()

    /// Whether we just mirror (false) or actively merge and upload (true).
    public static let shouldMergeBookmarks = true

    /// Flag indiciating if we are running in Debug mode or not.
    public static let isDebug: Bool = {
        #if MOZ_CHANNEL_FENNEC
            return true
        #else
            return false
        #endif
    }()

    /// Enables/disables the new Menu functionality
    public static let MOZ_MENU: Bool = {
        #if MOZ_CHANNEL_RELEASE
            return false
        #elseif MOZ_CHANNEL_BETA
            return false
        #elseif MOZ_CHANNEL_NIGHTLY
            return true
        #elseif MOZ_CHANNEL_FENNEC
            return true
        #elseif MOZ_CHANNEL_AURORA
            return true
        #else
            return true
        #endif
    }()

    ///  Enables/disables the notification bar that appears on the status bar area
    public static let MOZ_STATUS_BAR_NOTIFICATION: Bool = {
        #if MOZ_CHANNEL_RELEASE
            return false
        #elseif MOZ_CHANNEL_BETA
            return true
        #elseif MOZ_CHANNEL_NIGHTLY
            return true
        #elseif MOZ_CHANNEL_FENNEC
            return true
        #elseif MOZ_CHANNEL_AURORA
            return true
        #else
            return true
        #endif
    }()
}
