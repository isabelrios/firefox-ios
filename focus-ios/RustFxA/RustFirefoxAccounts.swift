/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import MozillaAppServices
import SwiftKeychainWrapper

/**
 A singleton that wraps the Rust FxA library.
 The singleton design is poor for testability through dependency injection and may need to be changed in future.
 */
// TODO: renamed FirefoxAccounts.swift once the old code is removed fully.
open class RustFirefoxAccounts {
    public static let prefKeyLastDeviceName = "prefKeyLastDeviceName"

    private let clientID = "1b1a3e44c54fbb58"
    public let redirectURL = "urn:ietf:wg:oauth:2.0:oob:oauth-redirect-webchannel"
    public static var shared = RustFirefoxAccounts()
    public let accountManager: FxAccountManager
    public var avatar: Avatar?
    private static var startupCalled = false
    public let syncAuthState: SyncAuthState
    fileprivate static var prefs: Prefs?
    public let pushNotifications = PushNotificationSetup()

    // This is used so that if a migration failed, show a UI indicator for the user to manually log in to their account.
    public var accountMigrationFailed: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "fxaccount-migration-failed")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "fxaccount-migration-failed")
        }
    }

    /** Must be called before this class is fully usable. Until this function is complete,
     all methods in this class will behave as if there is no Fx account.
     It will be called on app startup, and extensions must call this before using the class.
     If it is possible code could access `shared` before initialize() is complete, these callers should also
     hook into notifications like `.accountProfileUpdate` to refresh once initialize() is complete.

     The alternative implemention would be to have `shared` as a Deferred<RustFirefoxAccounts>. However that
     would require a significant rewrite of existing code, for minimal added benefit.
     */
    public static func startup(prefs _prefs: Prefs, completion: ((RustFirefoxAccounts) -> Void)? = nil) {
        prefs = _prefs
        if startupCalled {
            completion?(shared)
            return
        }
        startupCalled = true

        // Set-up Rust network stack. Note that this has to be called
        // before any Application Services component gets used.
        Viaduct.shared.useReqwestBackend()

        shared.accountManager.initialize() { result in
            let hasAttemptedMigration = UserDefaults.standard.bool(forKey: "hasAttemptedMigration")

            // Note this checks if startup() is called in an app extensions, and if so, do not try account migration
            if Bundle.main.bundleURL.pathExtension != "appex", let tokens = migrationTokens(), !hasAttemptedMigration {
                UserDefaults.standard.set(true, forKey: "hasAttemptedMigration")

                // The client app only needs to trigger this one time. If it fails due to offline state, the rust library
                // will automatically re-try until success or permanent failure (notifications accountAuthenticated / accountMigrationFailed respectively).
                // See also `init()` use of `.accountAuthenticated` below.
                shared.accountManager.authenticateViaMigration(sessionToken: tokens.session, kSync: tokens.ksync, kXCS: tokens.kxcs) { _ in }
            }

            if shared.accountManager.hasAccount() {
                NotificationCenter.default.post(name: .RegisterForPushNotifications, object: nil)
            }

            completion?(shared)
        }
    }

    private static let prefKeySyncAuthStateUniqueID = "PrefKeySyncAuthStateUniqueID"
    private static func syncAuthStateUniqueId(prefs: Prefs?) -> String {
        let id: String
        let key = RustFirefoxAccounts.prefKeySyncAuthStateUniqueID
        if let _id = prefs?.stringForKey(key) {
            id = _id
        } else {
            id = UUID().uuidString
            prefs?.setString(id, forKey: key)
        }
        return id
    }

    private init() {
        let prefs = RustFirefoxAccounts.prefs
        assert(prefs != nil)
        let server = prefs?.intForKey(PrefsKeys.UseStageServer) == 1 ? FxAConfig.Server.stage :
            (prefs?.boolForKey("useChinaSyncService") ?? AppInfo.isChinaEdition ? FxAConfig.Server.china : FxAConfig.Server.release)

        let config = FxAConfig(server: server, clientId: clientID, redirectUri: redirectURL)
        let type = UIDevice.current.userInterfaceIdiom == .pad ? DeviceType.tablet : DeviceType.mobile
        let deviceConfig = DeviceConfig(name: DeviceInfo.defaultClientName(), type: type, capabilities: [.sendTab])
        let accessGroupPrefix = Bundle.main.object(forInfoDictionaryKey: "MozDevelopmentTeam") as! String
        let accessGroupIdentifier = AppInfo.keychainAccessGroupWithPrefix(accessGroupPrefix)

        accountManager = FxAccountManager(config: config, deviceConfig: deviceConfig, applicationScopes: [OAuthScope.profile, OAuthScope.oldSync, OAuthScope.session], keychainAccessGroup: accessGroupIdentifier)

        syncAuthState = FirefoxAccountSyncAuthState(
            cache: KeychainCache.fromBranch("rustAccounts.syncAuthState",
                                            withLabel: RustFirefoxAccounts.syncAuthStateUniqueId(prefs: prefs),
                factory: syncAuthStateCachefromJSON))

        // Called when account is logged in for the first time, on every app start when the account is found (even if offline), and when migration of an account is completed.
        NotificationCenter.default.addObserver(forName: .accountAuthenticated, object: nil, queue: .main) { [weak self] notification in
            // Handle account migration completed successfully. Need to clear the old stored apnsToken and re-register push.
            if let type = notification.userInfo?["authType"] as? FxaAuthType, case .migrated = type {
                KeychainWrapper.sharedAppContainerKeychain.removeObject(forKey: "apnsToken", withAccessibility: .afterFirstUnlock)
                NotificationCenter.default.post(name: .RegisterForPushNotifications, object: nil)
            }

            self?.update()
        }
        
        NotificationCenter.default.addObserver(forName: .accountProfileUpdate, object: nil, queue: .main) { [weak self] notification in
            self?.update()
        }

        NotificationCenter.default.addObserver(forName: .accountMigrationFailed, object: nil, queue: .main) { [weak self] notification in
            var info = ""
            if let error = notification.userInfo?["error"] as? Error {
                info = error.localizedDescription
            }
            Sentry.shared.send(message: "RustFxa failed account migration", tag: .rustLog, severity: .error, description: info)
            self?.accountMigrationFailed = true
            NotificationCenter.default.post(name: .FirefoxAccountStateChange, object: nil)
        }
    }

    /// When migrating to new rust FxA, grab the old session tokens and try to re-use them.
    private class func migrationTokens() -> (session: String, ksync: String, kxcs: String)? {
        // Keychain forKey("profile.account"), return dictionary, from there
        // forKey("account.state.<guid>"), guid is dictionary["stateKeyLabel"]
        // that returns JSON string.
        let keychain = KeychainWrapper.sharedAppContainerKeychain
        let key = "profile.account"
        keychain.ensureObjectItemAccessibility(.afterFirstUnlock, forKey: key)
        guard let dict = keychain.object(forKey: key) as? [String: AnyObject], let guid = dict["stateKeyLabel"] else {
            return nil
        }

        let key2 = "account.state.\(guid)"
        keychain.ensureObjectItemAccessibility(.afterFirstUnlock, forKey: key2)
        guard let jsonData = keychain.data(forKey: key2) else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: jsonData, options: .allowFragments) as? [String: Any] else {
            return nil
        }

        guard let sessionToken = json["sessionToken"] as? String, let ksync = json["kSync"] as? String, let kxcs = json["kXCS"] as? String else {
            return nil
        }

        return (session: sessionToken, ksync: ksync, kxcs: kxcs)
    }

    /// This is typically used to add a UI indicator that FxA needs attention (usually re-login manually).
    public var isActionNeeded: Bool {
        if accountManager.accountMigrationInFlight() || accountMigrationFailed { return true }
        if !accountManager.hasAccount() { return false }
        return accountManager.accountNeedsReauth()
    }

    /// Rust FxA notification handlers can call this to update caches and the UI.
    private func update() {
        let avatarUrl = accountManager.accountProfile()?.avatar?.url
        if let str = avatarUrl, let url = URL(string: str) {
            avatar = Avatar(url: url)
        }

        // The userProfile (email, display name, etc) and the device name need to be cached for when the app starts in an offline state. Now is a good time to update those caches.

        // Accessing the profile will trigger a cache update if needed
        _ = userProfile

        // Update the device name cache
        if let deviceName = accountManager.deviceConstellation()?.state()?.localDevice?.displayName {
            UserDefaults.standard.set(deviceName, forKey: RustFirefoxAccounts.prefKeyLastDeviceName)
        }

        // The legacy system had both of these notifications for UI updates. Possibly they could be made into a single notification
        NotificationCenter.default.post(name: .FirefoxAccountProfileChanged, object: self)
        NotificationCenter.default.post(name: .FirefoxAccountStateChange, object: self)
    }

    /// Cache the user profile (i.e. email, user name) for when the app starts offline. Notice this gets cleared when an account is disconnected.
    private let prefKeyCachedUserProfile = "prefKeyCachedUserProfile"
    private var cachedUserProfile: FxAUserProfile?
    public var userProfile: FxAUserProfile? {
        get {
            let prefs = RustFirefoxAccounts.prefs

            if let profile = accountManager.accountProfile() {
                if let p = cachedUserProfile, FxAUserProfile(profile: profile) == p {
                    return cachedUserProfile
                }

                cachedUserProfile = FxAUserProfile(profile: profile)
                if let data = try? JSONEncoder().encode(cachedUserProfile!) {
                    prefs?.setObject(data, forKey: prefKeyCachedUserProfile)
                }
            } else if cachedUserProfile == nil {
                if let data: Data = prefs?.objectForKey(prefKeyCachedUserProfile) {
                    cachedUserProfile = try? JSONDecoder().decode(FxAUserProfile.self, from: data)
                }
            }

            return cachedUserProfile
        }
    }

    public func disconnect() {
        accountManager.logout() { _ in }
        let prefs = RustFirefoxAccounts.prefs
        prefs?.removeObjectForKey(RustFirefoxAccounts.prefKeySyncAuthStateUniqueID)
        prefs?.removeObjectForKey(prefKeyCachedUserProfile)
        cachedUserProfile = nil
    }
}

/**
 Wrap MozillaAppServices.Profile in an easy-to-serialize (and cache) FxAUserProfile.
 Caching of this is required for when the app starts offline.
 */
public struct FxAUserProfile: Codable, Equatable {
    public let uid: String
    public let email: String
    public let avatarUrl: String?
    public let displayName: String?

    init(profile: MozillaAppServices.Profile) {
        uid = profile.uid
        email = profile.email
        avatarUrl = profile.avatar?.url
        displayName = profile.displayName
    }
}
