/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import WebKit
import Shared
import Deferred

enum BlockList: String {
    case advertising = "disconnect-advertising"
    case analytics = "disconnect-analytics"
    case content = "disconnect-content"
    case social = "disconnect-social"

    var fileName: String { return self.rawValue }

    static var all: [BlockList] { return [.advertising, .analytics, .content, .social] }
    static var basic: [BlockList] { return [.advertising, .analytics, .social] }
    static var strict: [BlockList] { return [.content] }

    static func forStrictMode(isOn: Bool) -> [BlockList] {
        return BlockList.basic + (isOn ? BlockList.strict : [])
    }
}

@available(iOS 11.0, *)
class ContentBlockerHelper: NSObject {
    static let PrefKeyEnabledState = "prefkey.trackingprotection.enabled"
    static let PrefKeyStrength = "prefkey.trackingprotection.strength"

    fileprivate let ruleStore: WKContentRuleListStore
    fileprivate weak var tab: Tab?
    fileprivate weak var profile: Profile?

    static fileprivate var blockImagesRule: WKContentRuleList?
    static fileprivate var whitelistedDomains = [String]()

    // Only set and used in UI test
    static weak var testInstance: ContentBlockerHelper?

    fileprivate(set) var stats = TrackingInformation()

    func whitelist(enable: Bool, forDomain domain: String, completion: (() -> Void)?) {
        if enable {
            ContentBlockerHelper.whitelistedDomains.append(domain)
        } else {
            ContentBlockerHelper.whitelistedDomains = ContentBlockerHelper.whitelistedDomains.filter { $0 != domain }
        }

        BlockListChecker.shared.whitelistedDomains = ContentBlockerHelper.whitelistedDomains

        removeAllRulesInStore {
            self.compileListsNotInStore {
                NotificationCenter.default.post(name: .ContentBlockerUpdateNeeded, object: nil)
                completion?()
            }
        }

        guard let fileURL = whitelistFile else { return }
        let list = ContentBlockerHelper.whitelistedDomains.joined(separator: "\n")
        do {
            try list.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            Sentry.shared.send(message: "Failed to save whitelist file")
        }
    }

    enum PerTabOverrideEnabledState {
        case notSet
        case forceEnabledPerTab
        case forceDisabledPerTab
    }

    private(set) var perTabOverrideEnabledState: PerTabOverrideEnabledState = .notSet

    // Raw values are stored to prefs, be careful changing them.
    enum PrefEnabledState: String {
        case on
        case onInPrivateBrowsing
        case off

        var settingTitle: String {
            switch self {
            case .on:
                return Strings.TrackingProtectionOptionAlwaysOn
            case .onInPrivateBrowsing:
                return Strings.TrackingProtectionOptionOnInPrivateBrowsing
            case .off:
                return Strings.TrackingProtectionOptionAlwaysOff
            }
        }

        static func accessibilityId(for state: PrefEnabledState) -> String {
            switch state {
            case .on:
                return "Settings.TrackingProtectionOption.OnLabel"
            case .onInPrivateBrowsing:
                return "Settings.TrackingProtectionOption.OnInPrivateBrowsingLabel"
            case .off:
                return "Settings.TrackingProtectionOption.OffLabel"
            }
        }

        static let allOptions: [PrefEnabledState] = [.on, .onInPrivateBrowsing, .off]
    }

    // Raw values are stored to prefs, be careful changing them.
    enum BlockingStrength: String {
        case basic
        case strict

        var settingTitle: String {
            switch self {
            case .basic:
                return Strings.TrackingProtectionOptionBlockListTypeBasic
            case .strict:
                return Strings.TrackingProtectionOptionBlockListTypeStrict
            }
        }

        var subtitle: String {
            switch self {
            case .basic:
                return Strings.TrackingProtectionOptionBlockListTypeBasicDescription
            case .strict:
                return Strings.TrackingProtectionOptionBlockListTypeStrictDescription
            }
        }

        static func accessibilityId(for strength: BlockingStrength) -> String {
            switch strength {
            case .basic:
                return "Settings.TrackingProtectionOption.BlockListBasic"
            case .strict:
                return "Settings.TrackingProtectionOption.BlockListStrict"
            }
        }

        static let allOptions: [BlockingStrength] = [.basic, .strict]
    }

    static func prefsChanged() {
        NotificationCenter.default.post(name: .ContentBlockerUpdateNeeded, object: nil)
    }

    private static var heavyInitHasRunOnce = false

    private var whitelistFile: URL? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            Sentry.shared.send(message: "Failed to get doc dir for whitelist file.")
            return nil
        }
        return dir.appendingPathComponent("whitelist")
    }

    private func readWhitelistFile() -> String? {
        guard let fileURL = whitelistFile else { return nil }
        let text = try? String(contentsOf: fileURL, encoding: .utf8)
        return text
    }

    init(tab: Tab, profile: Profile) {
        self.ruleStore = WKContentRuleListStore.default()
        self.tab = tab
        self.profile = profile
        super.init()

        if AppConstants.IsRunningTest {
            ContentBlockerHelper.testInstance = self
        }

        if ContentBlockerHelper.heavyInitHasRunOnce {
            return
        }
        ContentBlockerHelper.heavyInitHasRunOnce = true

        // Read the whitelist at startup
        let text = readWhitelistFile()
        if let text = text, !text.isEmpty {
            ContentBlockerHelper.whitelistedDomains = text.components(separatedBy: .newlines)
        }

        removeOldListsByDateFromStore() {
            self.removeOldListsByNameFromStore() {
                self.compileListsNotInStore(completion: {})
            }
        }

        let blockImages = "[{'trigger':{'url-filter':'.*','resource-type':['image']},'action':{'type':'block'}}]".replacingOccurrences(of: "'", with: "\"")
        ruleStore.compileContentRuleList(forIdentifier: "images", encodedContentRuleList: blockImages) {
            rule, error in
            assert(rule != nil && error == nil)
            ContentBlockerHelper.blockImagesRule = rule
        }
    }

    func setupForWebView() {
        NotificationCenter.default.addObserver(self, selector: #selector(updateTab), name: .ContentBlockerUpdateNeeded, object: nil)
        addActiveRulesToTab()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func updateTab() {
        addActiveRulesToTab()
    }

    func overridePrefsAndReloadTab(enableTrackingProtection: Bool) {
        perTabOverrideEnabledState = enableTrackingProtection ? .forceEnabledPerTab : .forceDisabledPerTab
        updateTab()
        tab?.reload()
    }

    fileprivate var blockingStrengthPref: BlockingStrength {
        let pref = profile?.prefs.stringForKey(ContentBlockerHelper.PrefKeyStrength) ?? ""
        return BlockingStrength(rawValue: pref) ?? .basic
    }

    var prefEnabledState: PrefEnabledState {
        let pref = profile?.prefs.stringForKey(ContentBlockerHelper.PrefKeyEnabledState) ?? ""
        return PrefEnabledState(rawValue: pref) ?? .onInPrivateBrowsing
    }

    // Considers both the prefs state, and the per-tab override state.
    var isEnabledForTab: Bool {
        var prefEnabled: Bool
        switch prefEnabledState {
        case .off:
            return false
        case .on:
            prefEnabled = true
        case .onInPrivateBrowsing:
            prefEnabled = tab?.isPrivate ?? false
        }

        if perTabOverrideEnabledState != .notSet {
            return perTabOverrideEnabledState == .forceEnabledPerTab
        }

        return prefEnabled
    }

    fileprivate func addActiveRulesToTab() {
        removeTrackingProtectionFromTab()

        guard isEnabledForTab else {
            return
        }

        let rules = BlockList.forStrictMode(isOn: blockingStrengthPref == .strict)
        for list in rules {
            let name = list.fileName
            ruleStore.lookUpContentRuleList(forIdentifier: name) { rule, error in
                guard let rule = rule else {
                    let msg = "lookUpContentRuleList for \(name):  \(error?.localizedDescription ?? "empty rules")"
                    Sentry.shared.send(message: "Content blocker error", tag: .general, description: msg)
                    return
                }
                self.addToTab(contentRuleList: rule)
            }
        }
    }

    func removeTrackingProtectionFromTab() {
        guard let tab = tab else { return }
        tab.webView?.configuration.userContentController.removeAllContentRuleLists()

        if let rule = ContentBlockerHelper.blockImagesRule, tab.noImageMode {
            addToTab(contentRuleList: rule)
        }
    }

    fileprivate func addToTab(contentRuleList: WKContentRuleList) {
        tab?.webView?.configuration.userContentController.add(contentRuleList)
    }

    func noImageMode(enabled: Bool) {
        guard let rule = ContentBlockerHelper.blockImagesRule else { return }

        if enabled {
            addToTab(contentRuleList: rule)
        } else {
            tab?.webView?.configuration.userContentController.remove(rule)
        }

        // Async required here to ensure remove() call is processed.
        DispatchQueue.main.async() {
            self.tab?.webView?.evaluateJavaScript("window.__firefox__.NoImageMode.setEnabled(\(enabled))", completionHandler: nil)
        }
    }
}

// MARK: Private initialization code
// The rule store can compile JSON rule files into a private format which is cached on disk.
// On app boot, we need to check if the ruleStore's data is out-of-date, or if the names of the rule files
// no longer match. Finally, any JSON rule files that aren't in the ruleStore need to be compiled and stored in the
// ruleStore.
@available(iOS 11, *)
extension ContentBlockerHelper {
    fileprivate func loadJsonFromBundle(forResource file: String, completion: @escaping (_ jsonString: String) -> Void) {
        DispatchQueue.global().async {
            guard let path = Bundle.main.path(forResource: file, ofType: "json"),
                let source = try? String(contentsOfFile: path, encoding: .utf8) else {
                    return
            }

            DispatchQueue.main.async {
                completion(source)
            }
        }
    }

    fileprivate func lastModifiedSince1970(forFileAtPath path: String) -> Timestamp? {
        do {
            let url = URL(fileURLWithPath: path)
            let attr = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let date = attr[FileAttributeKey.modificationDate] as? Date else { return nil }
            return UInt64(1000.0 * date.timeIntervalSince1970)
        } catch {
            return nil
        }
    }

    fileprivate func dateOfMostRecentBlockerFile() -> Timestamp {
        let blocklists = BlockList.all
        return blocklists.reduce(Timestamp(0)) { result, list in
            guard let path = Bundle.main.path(forResource: list.fileName, ofType: "json") else { return result }
            let date = lastModifiedSince1970(forFileAtPath: path) ?? 0
            return date > result ? date : result
        }
    }

    fileprivate func removeAllRulesInStore(completion: @escaping () -> Void) {
        ruleStore.getAvailableContentRuleListIdentifiers { available in
            guard let available = available else {
                completion()
                return
            }
            let deferreds: [Deferred<Void>] = available.map { filename in
                let result = Deferred<Void>()
                self.ruleStore.removeContentRuleList(forIdentifier: filename) { _ in
                   result.fill()
                }
                return result
            }
            all(deferreds).uponQueue(.main) { _ in
                completion()
            }
        }
    }

    // If any blocker files are newer than the date saved in prefs,
    // remove all the content blockers and reload them.
    fileprivate func removeOldListsByDateFromStore(completion: @escaping () -> Void) {
        let fileDate = self.dateOfMostRecentBlockerFile()
        let prefsNewestDate = profile?.prefs.longForKey("blocker-file-date") ?? 0
        if prefsNewestDate < 1 || fileDate <= prefsNewestDate {
            completion()
            return
        }

        profile?.prefs.setTimestamp(fileDate, forKey: "blocker-file-date")
        self.removeAllRulesInStore() {
            completion()
        }
    }

    fileprivate func removeOldListsByNameFromStore(completion: @escaping () -> Void) {
        var noMatchingIdentifierFoundForRule = false

        ruleStore.getAvailableContentRuleListIdentifiers { available in
            guard let available = available else {
                completion()
                return
            }

            let blocklists = BlockList.all.map { $0.fileName }
            for contentRuleIdentifier in available {
                if !blocklists.contains(where: { $0 == contentRuleIdentifier }) {
                    noMatchingIdentifierFoundForRule = true
                    break
                }
            }

            let fileDate = self.dateOfMostRecentBlockerFile()
            let prefsNewestDate = self.profile?.prefs.timestampForKey("blocker-file-date") ?? 0
            if prefsNewestDate > 0 && fileDate <= prefsNewestDate && !noMatchingIdentifierFoundForRule {
                completion()
                return
            }
            self.profile?.prefs.setTimestamp(fileDate, forKey: "blocker-file-date")

            self.removeAllRulesInStore {
                completion()
            }
        }
    }

    fileprivate func compileListsNotInStore(completion: @escaping () -> Void) {
        let blocklists = BlockList.all.map { $0.fileName}
        let deferreds: [Deferred<Void>] = blocklists.map { filename in
            let result = Deferred<Void>()
            ruleStore.lookUpContentRuleList(forIdentifier: filename) { contentRuleList, error in
                if contentRuleList != nil {
                    result.fill()
                    return
                }
                self.loadJsonFromBundle(forResource: filename) { jsonString in
                    var str = jsonString
                    str.insert(contentsOf: self.whitelistJSON(), at: str.index(str.endIndex, offsetBy: -1) )
                    self.ruleStore.compileContentRuleList(forIdentifier: filename, encodedContentRuleList: str) { _, _ in
                        result.fill()
                    }
                }
            }
            return result
        }

        all(deferreds).uponQueue(.main) { _ in
            completion()
        }
    }

    func whitelistJSON() -> String {
        if ContentBlockerHelper.whitelistedDomains.isEmpty {
            return ""
        }
        // Note that * is added to the front of domains, so foo.com becomes *foo.com
        let list = "'*" + ContentBlockerHelper.whitelistedDomains.joined(separator: "','*") + "'"
        return ", {'action': { 'type': 'ignore-previous-rules' }, 'trigger': { 'url-filter': '.*', 'unless-domain': [\(list)] }".replacingOccurrences(of: "'", with: "\"")
    }
}

@available(iOS 11, *)
extension ContentBlockerHelper : TabContentScript {
    class func name() -> String {
        return "TrackingProtectionStats"
    }

    func scriptMessageHandlerName() -> String? {
        return "trackingProtectionStats"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        guard isEnabledForTab, let body = message.body as? [String: String], let urlString = body["url"] else {
            return
        }

        guard var components = URLComponents(string: urlString) else { return }
        components.scheme = "http"
        guard let url = components.url else { return }

        if let listItem = BlockListChecker.shared.isBlocked(url: url, isStrictMode: blockingStrengthPref == .strict) {
            stats = stats.create(byAddingListItem: listItem)
        }
    }

}
