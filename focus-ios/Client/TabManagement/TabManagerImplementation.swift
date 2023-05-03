// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import TabDataStore
import Storage
import Common
import Shared

// This class subclasses the legacy tab manager temporarily so we can
// gradually migrate to the new system
class TabManagerImplementation: LegacyTabManager {
    let tabDataStore: TabDataStore
    let tabSessionStore: TabSessionStore
    let imageStore: DiskImageStore?
    lazy var isNewTabStoreEnabled: Bool = TabStorageFlagManager.isNewTabDataStoreEnabled

    init(profile: Profile,
         imageStore: DiskImageStore?,
         logger: Logger = DefaultLogger.shared,
         tabDataStore: TabDataStore = DefaultTabDataStore(),
         tabSessionStore: TabSessionStore = DefaultTabSessionStore()) {
        self.tabDataStore = tabDataStore
        self.tabSessionStore = tabSessionStore
        self.imageStore = imageStore
        super.init(profile: profile, imageStore: imageStore)
    }

    // MARK: - Restore tabs

    override func restoreTabs(_ forced: Bool = false) {
        guard shouldUseNewTabStore()
        else {
            super.restoreTabs(forced)
            return
        }

        guard !isRestoringTabs else { return }

        // TODO: FXIOS-6112 Handle debug settings and UITests

        if forced {
            tabs = [Tab]()
        }

        isRestoringTabs = true
        Task {
            guard let windowData = await self.tabDataStore.fetchWindowData()
            else {
                // Always make sure there is a single normal tab
                await self.generateEmptyTab()
                return
            }

            await self.generateTabs(from: windowData)

            for delegate in self.delegates {
                delegate.get()?.tabManagerDidRestoreTabs(self)
            }

            self.isRestoringTabs = false
        }
    }

    /// Creates the webview so needs to live on the main thread
    @MainActor
    private func generateTabs(from windowData: WindowData) async {
        for tabData in windowData.tabData {
            let newTab = addTab(flushToDisk: false, zombie: true, isPrivate: tabData.isPrivate)
            newTab.url = URL(string: tabData.siteUrl)
            newTab.lastTitle = tabData.title
            newTab.tabUUID = tabData.id.uuidString
            newTab.screenshotUUID = tabData.id
            newTab.firstCreatedTime = tabData.createdAtTime.toTimestamp()
            newTab.sessionData = LegacySessionData(currentPage: 0,
                                                   urls: [],
                                                   lastUsedTime: tabData.lastUsedTime.toTimestamp())
            let groupData = LegacyTabGroupData(searchTerm: tabData.tabGroupData?.searchTerm ?? "",
                                               searchUrl: tabData.tabGroupData?.searchUrl ?? "",
                                               nextReferralUrl: tabData.tabGroupData?.nextUrl ?? "",
                                               tabHistoryCurrentState: tabData.tabGroupData?.tabHistoryCurrentState?.rawValue ?? "")
            newTab.metadataManager?.tabGroupData = groupData

            if windowData.activeTabId == tabData.id {
                selectTab(newTab)
            }
        }
    }

    /// Creates the webview so needs to live on the main thread
    @MainActor
    private func generateEmptyTab() {
        let newTab = addTab()
        selectTab(newTab)
    }

    // MARK: - Save tabs

    override func preserveTabs() {
        // For now we want to continue writing to both data stores so that we can revert to the old system if needed
        super.preserveTabs()
        guard shouldUseNewTabStore() else { return }

        Task {
            // This value should never be nil but we need to still treat it as if it can be nil until the old code is removed
            let activeTabID = UUID(uuidString: self.selectedTab?.tabUUID ?? "") ?? UUID()
            // Hard coding the window ID until we later add multi-window support
            let windowData = WindowData(id: UUID(uuidString: "44BA0B7D-097A-484D-8358-91A6E374451D")!,
                                        activeTabId: activeTabID,
                                        tabData: self.generateTabDataForSaving())
            await tabDataStore.saveWindowData(window: windowData)
        }
    }

    private func generateTabDataForSaving() -> [TabData] {
        let tabData = tabs.map { tab in
            let oldTabGroupData = tab.metadataManager?.tabGroupData
            let state = TabGroupTimerState(rawValue: oldTabGroupData?.tabHistoryCurrentState ?? "")
            let groupData = TabGroupData(searchTerm: oldTabGroupData?.tabAssociatedSearchTerm,
                                         searchUrl: oldTabGroupData?.tabAssociatedSearchUrl,
                                         nextUrl: oldTabGroupData?.tabAssociatedNextUrl,
                                         tabHistoryCurrentState: state)
            return TabData(id: UUID(uuidString: tab.tabUUID) ?? UUID(),
                           title: tab.title ?? tab.lastTitle,
                           siteUrl: tab.url?.absoluteString ?? "",
                           faviconURL: tab.faviconURL,
                           isPrivate: tab.isPrivate,
                           lastUsedTime: Date.fromTimestamp(tab.sessionData?.lastUsedTime ?? 0),
                           createdAtTime: Date.fromTimestamp(tab.firstCreatedTime ?? 0),
                           tabGroupData: groupData)
        }
        return tabData
    }

    /// storeChanges is called when a web view has finished loading a page
    override func storeChanges() {
        guard shouldUseNewTabStore()
        else {
            super.storeChanges()
            return
        }

        saveTabs(toProfile: profile, normalTabs)
        preserveTabs()
        saveIndividualTabSessionData()
    }

    private func saveIndividualTabSessionData() {
        guard #available(iOS 15.0, *),
              let selectedTab = self.selectedTab,
              let tabSession = selectedTab.webView?.interactionState as? Data,
              let tabID = UUID(uuidString: selectedTab.tabUUID)
        else { return }

        Task {
            await self.tabSessionStore.saveTabSession(tabID: tabID, sessionData: tabSession)
        }
    }

    // MARK: - Select Tab
    override func selectTab(_ tab: Tab?, previous: Tab? = nil) {
        guard shouldUseNewTabStore(),
              let tab = tab,
              let tabUUID = UUID(uuidString: tab.tabUUID)
        else {
            super.selectTab(tab, previous: previous)
            return
        }

        guard tab.tabUUID != selectedTab?.tabUUID else { return }

        Task {
            let sessionData = await tabSessionStore.fetchTabSession(tabID: tabUUID)
            await selectTabWithSession(tab: tab,
                                       previous: previous,
                                       sessionData: sessionData)
        }
    }

    @MainActor
    private func selectTabWithSession(tab: Tab, previous: Tab?, sessionData: Data?) {
        super.selectTab(tab, previous: previous, sessionData: sessionData)
    }

    private func shouldUseNewTabStore() -> Bool {
        if #available(iOS 15, *), isNewTabStoreEnabled {
            return true
        }
        return false
    }

    // MARK: - Save screenshot
    override func tabDidSetScreenshot(_ tab: Tab, hasHomeScreenshot: Bool) {
        guard shouldUseNewTabStore()
        else {
            super.tabDidSetScreenshot(tab, hasHomeScreenshot: hasHomeScreenshot)
            return
        }

        storeScreenshot(tab: tab)
    }

    override func storeScreenshot(tab: Tab) {
        guard shouldUseNewTabStore(),
              let screenshot = tab.screenshot
        else {
            super.storeScreenshot(tab: tab)
            return
        }

        Task {
            try await imageStore?.saveImageForKey(tab.tabUUID, image: screenshot)
        }
    }

    override func removeScreenshot(tab: Tab) {
        guard shouldUseNewTabStore()
        else {
            super.removeScreenshot(tab: tab)
            return
        }

        Task {
            await imageStore?.deleteImageForKey(tab.tabUUID)
        }
    }
}
