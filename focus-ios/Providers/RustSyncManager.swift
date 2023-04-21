// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import Shared
import Storage
import Sync
import SyncTelemetry
import AuthenticationServices
import Common

private typealias MZSyncResult = MozillaAppServices.SyncResult

// Extends NSObject so we can use timers.
public class RustSyncManager: NSObject, SyncManager {
    // We shouldn't live beyond our containing BrowserProfile, either in the main app
    // or in an extension.
    // But it's possible that we'll finish a side-effect sync after we've ditched the
    // profile as a whole, so we hold on to our Prefs, potentially for a little while
    // longer. This is safe as a strong reference, because there's no cycle.
    private weak var profile: BrowserProfile?
    private let prefs: Prefs
    private var syncTimer: Timer?
    private var backgrounded = true
    private let logger: Logger
    private let fxaDeclinedEngines = "fxa.cwts.declinedSyncEngines"
    private var notificationCenter: NotificationProtocol

    let fifteenMinutesInterval = TimeInterval(60 * 15)

    public var lastSyncFinishTime: Timestamp? {
        get {
            return prefs.timestampForKey(PrefsKeys.KeyLastSyncFinishTime)
        }

        set(value) {
            if let value = value {
                prefs.setTimestamp(value,
                                   forKey: PrefsKeys.KeyLastSyncFinishTime)
            } else {
                prefs.removeObjectForKey(PrefsKeys.KeyLastSyncFinishTime)
            }
        }
    }

    lazy var syncManagerAPI = RustSyncManagerAPI(logger: logger)

    public var isSyncing: Bool {
        return syncDisplayState != nil && syncDisplayState! == .inProgress
    }

    public var syncDisplayState: SyncDisplayState?

    var prefsForSync: Prefs {
        return prefs.branch("sync")
    }

    init(profile: BrowserProfile,
         logger: Logger = DefaultLogger.shared,
         notificationCenter: NotificationProtocol = NotificationCenter.default) {
        self.profile = profile
        self.prefs = profile.prefs
        self.logger = logger
        self.notificationCenter = notificationCenter

        super.init()
    }

    @objc
    func syncOnTimer() {
        syncEverything(why: .scheduled)
        profile?.pollCommands()
    }

    private func repeatingTimerAtInterval(
        _ interval: TimeInterval,
        selector: Selector
    ) -> Timer {
        return Timer.scheduledTimer(timeInterval: interval,
                                    target: self,
                                    selector: selector,
                                    userInfo: nil,
                                    repeats: true)
    }

    func syncEverythingSoon() {
        doInBackgroundAfter(SyncConstants.SyncOnForegroundAfterMillis) {
            self.logger.log("Running delayed startup sync.",
                            level: .debug,
                            category: .sync)
            self.syncEverything(why: .startup)
        }
    }

    private func beginTimedSyncs() {
        if syncTimer != nil {
            logger.log("Already running sync timer.",
                       level: .debug,
                       category: .sync)
            return
        }

        let interval = fifteenMinutesInterval
        let selector = #selector(syncOnTimer)
        logger.log("Starting sync timer.",
                   level: .info,
                   category: .sync)
        syncTimer = repeatingTimerAtInterval(interval, selector: selector)
    }

    /**
     * The caller is responsible for calling this on the same thread on which it called
     * beginTimedSyncs.
     */
    public func endTimedSyncs() {
        if let timer = syncTimer {
            logger.log("Stopping sync timer.",
                       level: .info,
                       category: .sync)
            syncTimer = nil
            timer.invalidate()
        }
    }

    public func applicationDidBecomeActive() {
        backgrounded = false

        guard let profile = profile, profile.hasSyncableAccount() else { return }

        beginTimedSyncs()

        // Sync now if it's been more than our threshold.
        let now = Date.now()
        let then = lastSyncFinishTime ?? 0
        guard now >= then else {
            logger.log("Time was modified since last sync.",
                       level: .debug,
                       category: .sync)
            syncEverythingSoon()
            return
        }
        let since = now - then
        logger.log("\(since)msec since last sync.",
                   level: .debug,
                   category: .sync)
        if since > SyncConstants.SyncOnForegroundMinimumDelayMillis {
            syncEverythingSoon()
        }
    }

    public func applicationDidEnterBackground() {
        backgrounded = true
    }

    private func beginSyncing() {
        syncDisplayState = .inProgress
        notifySyncing(notification: .ProfileDidStartSyncing)
    }

    private func resolveSyncState(result: MZSyncResult) -> SyncDisplayState {
        let hasSynced = !result.successful.isEmpty
        let status = result.status

        // This is similar to the old `SyncStatusResolver.resolveResults` call. If none of
        // the engines successfully synced and a network issue occured we return `.bad`.
        // If none of the engines successfully synced and an auth error occured we return
        // `.warning`. Otherwise we return `.good`.

        if !hasSynced && status == .authError {
            return .warning(message: .FirefoxSyncOfflineTitle)
        } else if !hasSynced && status == .networkError {
            return .bad(message: .FirefoxSyncOfflineTitle)
        } else {
            return .good
        }
    }

    private func endSyncing(_ result: MZSyncResult) {
        logger.log("Ending all syncs.",
                   level: .info,
                   category: .sync)

        syncDisplayState = resolveSyncState(result: result)

        if let syncState = syncDisplayState, syncState == .good {
            lastSyncFinishTime = Date.now()
        }

        if canSendUsageData() {
            self.syncManagerAPI.reportSyncTelemetry(syncResult: result) {_ in }
        } else {
            logger.log("Profile isn't sending usage data. Not sending sync status event.",
                       level: .debug,
                       category: .sync)
        }

        // Don't notify if we are performing a sync in the background. This prevents more
        // db access from happening
        if !backgrounded {
            notifySyncing(notification: .ProfileDidFinishSyncing)
        }
    }

    func canSendUsageData() -> Bool {
        return profile?.prefs.boolForKey(AppConstants.prefSendUsageData) ?? true
    }

    private func notifySyncing(notification: Notification.Name) {
        notificationCenter.post(name: notification)
    }

    func doInBackgroundAfter(_ millis: Int64, _ block: @escaping () -> Void) {
        let queue = DispatchQueue.global(qos: DispatchQoS.background.qosClass)
        queue.asyncAfter(
            deadline: DispatchTime.now() + DispatchTimeInterval.milliseconds(Int(millis)),
            execute: block)
    }

    public func onAddedAccount() -> Success {
        // Only sync if we're green lit. This makes sure that we don't sync unverified
        // accounts.
        guard let profile = profile, profile.hasSyncableAccount() else { return succeed() }

        beginTimedSyncs()
        return syncEverything(why: .didLogin)
    }

    public func onRemovedAccount() -> Success {
        let clearPrefs: () -> Success = {
            withExtendedLifetime(self) {
                // Clear prefs after we're done clearing everything else -- just in case
                // one of them needs the prefs and we race. Clear regardless of success
                // or failure.

                // This will remove keys from the Keychain if they exist, as well
                // as wiping the Sync prefs.

                // `Scratchpad.clearFromPrefs` and `clearAll` were pulled from
                // `SyncStateMachine.clearStateFromPrefs` to reduce RustSyncManager's
                // dependence on the swift sync state machine logic. This will make
                // refactoring or eliminating that code easier once the rust sync manager
                // experiment is complete.
                Scratchpad.clearFromPrefs(self.prefsForSync.branch("scratchpad"))
                self.prefsForSync.clearAll()
            }
            return succeed()
        }
        self.syncManagerAPI.disconnect()
        return clearPrefs()
    }

    private func getEngineEnablementChangesForAccount() -> [String: Bool] {
        var engineEnablements: [String: Bool] = [:]
        // We just created the account, the user went through the Choose What to Sync
        // screen on FxA.
        if let declined = UserDefaults.standard.stringArray(forKey: fxaDeclinedEngines) {
            declined.forEach { engineEnablements[$0] = false }
            UserDefaults.standard.removeObject(forKey: fxaDeclinedEngines)
        } else {
            // Bundle in authState the engines the user activated/disabled since the
            // last sync.
            RustTogglableEngines.forEach { engine in
                let stateChangedPref = "engine.\(engine).enabledStateChanged"
                if prefsForSync.boolForKey(stateChangedPref) != nil,
                   let enabled = prefsForSync.boolForKey("engine.\(engine).enabled") {
                    engineEnablements[engine] = enabled
                }
            }
        }

        if !engineEnablements.isEmpty {
            let enabled = engineEnablements.compactMap { $0.value ? $0.key : nil }
            logger.log("engines to enable: \(enabled)",
                       level: .info,
                       category: .sync)

            let disabled = engineEnablements.compactMap { !$0.value ? $0.key : nil }
            let msg = "engines to disable: \(disabled)"
            logger.log(msg,
                       level: .info,
                       category: .sync)
        }
        return engineEnablements
    }

    public class ScopedKeyError: MaybeErrorType {
        public let description = "No key data found for scope."
    }

    public class EncryptionKeyError: MaybeErrorType {
        public let description = "Failed to get stored key."
    }

    public class DeviceIdError: MaybeErrorType {
        public let description = "Failed to get deviceId."
    }

    public class NoTokenServerURLError: MaybeErrorType {
        public let description = "Failed to get token server endpoint url."
    }

    public class EngineAndKeyRetrievalError: MaybeErrorType {
        public let description = "Failed to get sync engine and key data."
    }

    private func getEnginesAndKeys(engines: [String]) -> Deferred<Maybe<([EngineIdentifier],
                                                                         [String: String])>> {
        let deferred = Deferred<Maybe<([EngineIdentifier], [String: String])>>()
        var localEncryptionKeys: [String: String] = [:]
        var rustEngines: [String] = []
        var registeredPlaces = false

        for engine in engines {
            switch engine {
            case "tabs":
                profile?.tabs.registerWithSyncManager()
                rustEngines.append(engine)
            case "passwords":
                profile?.logins.registerWithSyncManager()
                if let key = try? profile?.logins.getStoredKey() {
                    localEncryptionKeys[engine] = key
                    rustEngines.append(engine)
                } else {
                    logger.log("Login encryption key could not be retrieved for syncing",
                               level: .warning,
                               category: .sync)
                }
            case "bookmarks", "history":
                if !registeredPlaces {
                    profile?.places.registerWithSyncManager()
                    registeredPlaces = true
                }
                rustEngines.append(engine)
            default:
                continue
            }
        }

        deferred.fill(Maybe(success: (rustEngines, localEncryptionKeys)))
        return deferred
    }

    private func syncRustEngines(why: MozillaAppServices.SyncReason,
                                 engines: [String]) -> Deferred<Maybe<MZSyncResult>> {
        let deferred = Deferred<Maybe<MZSyncResult>>()

        logger.log("Syncing \(engines)", level: .info, category: .sync)
        self.profile?.rustFxA.accountManager.upon { accountManager in
            guard let device = accountManager.deviceConstellation()?
                .state()?
                .localDevice else {
                self.logger.log("Device Id could not be retrieved",
                                level: .warning,
                                category: .sync)
                deferred.fill(Maybe(failure: DeviceIdError()))
                return
            }

            accountManager.getAccessToken(scope: OAuthScope.oldSync) { result in
                guard let accessTokenInfo = try? result.get(),
                      let key = accessTokenInfo.key else {
                    deferred.fill(Maybe(failure: ScopedKeyError()))
                    return
                }

                accountManager.getTokenServerEndpointURL { result in
                    guard case .success(let tokenServerEndpointURL) = result else {
                        deferred.fill(Maybe(failure: NoTokenServerURLError()))
                        return
                    }

                    self.getEnginesAndKeys(engines: engines).upon { result in
                        guard let (rustEngines, localEncryptionKeys) = result.successValue else {
                            deferred.fill(Maybe(failure: EngineAndKeyRetrievalError()))
                            return
                        }
                        let params = SyncParams(
                            reason: why,
                            engines: SyncEngineSelection.some(engines: rustEngines),
                            enabledChanges: self.getEngineEnablementChangesForAccount(),
                            localEncryptionKeys: localEncryptionKeys,
                            authInfo: SyncAuthInfo(
                                kid: key.kid,
                                fxaAccessToken: accessTokenInfo.token,
                                syncKey: key.k,
                                tokenserverUrl: tokenServerEndpointURL.absoluteString),
                            persistedState:
                                self.prefs
                                    .stringForKey(PrefsKeys.RustSyncManagerPersistedState),
                            deviceSettings: DeviceSettings(
                                fxaDeviceId: device.id,
                                name: device.displayName,
                                kind: self.toSyncManagerDeviceType(
                                    deviceType: device.deviceType)))

                        self.beginSyncing()
                        self.syncManagerAPI.sync(params: params) { syncResult in
                            // Save the persisted state
                            if !syncResult.persistedState.isEmpty {
                                self.prefs
                                    .setString(syncResult.persistedState,
                                               forKey: PrefsKeys.RustSyncManagerPersistedState)
                            }

                            let declinedEngines = String(describing: syncResult.declined ?? [])
                            let telemetryData = syncResult.telemetryJson ??
                                "(No telemetry data was returned)"
                            let telemetryMessage = "\(String(describing: telemetryData))"
                            let syncDetails = ["status": "\(syncResult.status)",
                                               "declinedEngines": "\(declinedEngines)",
                                               "telemetry": telemetryMessage]

                            self.logger.log("Finished syncing",
                                            level: .info,
                                            category: .sync,
                                            extra: syncDetails)

                            // Save declined/enabled engines - we assume the engines
                            // not included in the returned `declined` property of the
                            // result of the sync manager `sync` are enabled.
                            let updateEnginePref:
                            (String, Bool) -> Void = { engine, enabled in
                                let enabledPref = "engine.\(engine).enabled"
                                self.prefsForSync.setBool(enabled, forKey: enabledPref)

                                let stateChangedPref = "engine.\(engine).enabledStateChanged"
                                self.prefsForSync.setObject(nil, forKey: stateChangedPref)

                                let enablementDetails = [enabledPref: String(enabled)]
                                self.logger.log("Finished setting \(engine) enablement prefs",
                                                level: .info,
                                                category: .sync,
                                                extra: enablementDetails)
                            }

                            if let declined = syncResult.declined {
                                RustTogglableEngines.forEach({
                                    if declined.contains($0) {
                                        updateEnginePref($0, false)
                                    } else {
                                        updateEnginePref($0, true)
                                    }
                                })
                            }

                            deferred.fill(Maybe(success: syncResult))
                            self.endSyncing(syncResult)
                        }
                    }
                }
            }
        }
        return deferred
    }

    private func toSyncManagerDeviceType(deviceType: DeviceType) -> SyncManagerDeviceType {
        switch deviceType {
        case .desktop:
            return SyncManagerDeviceType.desktop
        case .mobile:
            return SyncManagerDeviceType.mobile
        case .tablet:
            return SyncManagerDeviceType.tablet
        case .vr:
            return SyncManagerDeviceType.vr
        case .tv:
            return SyncManagerDeviceType.tv
        case .unknown:
            return SyncManagerDeviceType.unknown
        }
    }

    @discardableResult
    public func syncEverything(why: OldSyncReason) -> Success {
        let rustReason = toRustSyncReason(reason: why)
        return syncRustEngines(why: rustReason, engines: RustTogglableEngines) >>> succeed
    }

    /**
     * Allows selective sync of different collections, for use by external APIs.
     * Some help is given to callers who use different namespaces (specifically: `passwords` is mapped to `logins`)
     * and to preserve some ordering rules.
     */
    public func syncNamedCollections(why: OldSyncReason, names: [String]) -> Success {
        // Massage the list of names into engine identifiers.var engines = [String]()
        var engines = [String]()

        // There may be duplicates in `names` so we are removing them here
        for name in names where !engines.contains(name) {
            engines.append(name)
        }

        // Ensuring that only valid engines are submitted
        let filteredEngines = engines.filter { RustTogglableEngines.contains($0) }

        let rustReason = toRustSyncReason(reason: why)
        return syncRustEngines(why: rustReason, engines: filteredEngines) >>> succeed
    }

    private func syncTabs() -> Deferred<Maybe<MZSyncResult>> {
        return syncRustEngines(why: .user, engines: ["tabs"])
    }

    public func syncClientsThenTabs() -> OldSyncResult {
        // This function exists to comply with the `SyncManager` protocol while the
        // rust sync manager experiment is enabled. To be safe, `syncTabs` is called. Once
        // the experiment is complete this can be removed along with an update to the
        // protocol.

        return syncTabs().bind { result in
            if let error = result.failureValue {
                return deferMaybe(error)
            }

            // The current callers of `BrowserSyncManager.syncClientsThenTabs` only care
            // whether the function fails or succeeds and does nothing with return value
            // upon success so we are returning a meaningless value here.
            return deferMaybe(SyncStatus.notStarted(SyncNotStartedReason.unknown))
        }
    }

    public func syncClients() -> OldSyncResult {
        // This function exists to to comply with the `SyncManager` protocol and has
        // no callers. It will be removed when the rust sync manager experiment is
        // complete. To be safe, `syncClientsThenTabs` is called.
        return syncClientsThenTabs()
    }

    public func syncHistory() -> OldSyncResult {
        // The return type of this function has been changed to comply with the
        // `SyncManager` protocol during the rust sync manager experiment. It will be updated
        // once the experiment is complete.
        return syncRustEngines(why: .user, engines: ["history"]).bind { result in
            if let error = result.failureValue {
                return deferMaybe(error)
            }

            // The current callers of this function only care whether this function fails
            // or succeeds and does nothing with return value upon success so we are
            // returning a meaningless value here.
            return deferMaybe(SyncStatus.notStarted(SyncNotStartedReason.unknown))
        }
    }
}
