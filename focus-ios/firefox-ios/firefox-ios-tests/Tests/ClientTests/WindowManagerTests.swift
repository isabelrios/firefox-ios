// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import XCTest
import Shared
import Common
import Storage
import TabDataStore
@testable import Client

class WindowManagerTests: XCTestCase {
    let tabManager = MockTabManager()
    let secondTabManager = MockTabManager()

    override func setUp() {
        super.setUp()
        DependencyHelperMock().bootstrapDependencies(injectedTabManager: tabManager)
    }

    override func tearDown() {
        super.tearDown()
        DependencyHelperMock().reset()
    }

    func testConfiguringAndConnectingSingleAppWindow() {
        let subject = createSubject()

        // Connect TabManager and browser to app window
        let uuid = tabManager.windowUUID
        subject.newBrowserWindowConfigured(AppWindowInfo(tabManager: tabManager), uuid: uuid)

        // Expect 1 app window is now configured
        XCTAssertEqual(1, subject.windows.count)
        // Expect that window is now active window
        XCTAssertEqual(uuid, subject.activeWindow)
        // Expect our previous tab manager is associated with that window
        XCTAssert(tabManager === subject.tabManager(for: uuid))
        XCTAssertEqual(tabManager.windowUUID, uuid)
    }

    func testConfiguringAndConnectingMultipleAppWindows() {
        let subject = createSubject()

        // Connect first TabManager and browser to app window
        let firstWindowUUID = tabManager.windowUUID
        subject.newBrowserWindowConfigured(AppWindowInfo(tabManager: tabManager), uuid: firstWindowUUID)
        // Expect 1 app window is now configured
        XCTAssertEqual(1, subject.windows.count)

        // Connect second TabManager and browser to another window
        let secondWindowUUID = secondTabManager.windowUUID
        subject.newBrowserWindowConfigured(AppWindowInfo(tabManager: secondTabManager), uuid: secondWindowUUID)

        // Expect 2 app windows are now configured
        XCTAssertEqual(2, subject.windows.count)
        // Expect that our first window is still the active window
        XCTAssertEqual(firstWindowUUID, subject.activeWindow)

        // Check for expected tab manager references for each window
        XCTAssert(tabManager === subject.tabManager(for: firstWindowUUID))
        XCTAssertEqual(tabManager.windowUUID, firstWindowUUID)
        XCTAssert(secondTabManager === subject.tabManager(for: secondWindowUUID))
        XCTAssertEqual(secondTabManager.windowUUID, secondWindowUUID)
    }

    func testChangingActiveWindow() {
        var subject = createSubject()

        // Configure two app windows
        let firstWindowUUID = tabManager.windowUUID
        let secondWindowUUID = secondTabManager.windowUUID
        subject.newBrowserWindowConfigured(AppWindowInfo(tabManager: tabManager), uuid: firstWindowUUID)
        subject.newBrowserWindowConfigured(AppWindowInfo(tabManager: secondTabManager), uuid: secondWindowUUID)

        XCTAssertEqual(subject.activeWindow, firstWindowUUID)
        subject.activeWindow = secondWindowUUID
        XCTAssertEqual(subject.activeWindow, secondWindowUUID)
    }

    func testOpeningMultipleWindowsAndClosingTheFirstWindow() {
        let subject = createSubject()

        // Configure two app windows
        let firstWindowUUID = tabManager.windowUUID
        let secondWindowUUID = secondTabManager.windowUUID
        subject.newBrowserWindowConfigured(AppWindowInfo(tabManager: tabManager), uuid: firstWindowUUID)
        subject.newBrowserWindowConfigured(AppWindowInfo(tabManager: secondTabManager), uuid: secondWindowUUID)

        // Check that first window is the active window
        XCTAssertEqual(2, subject.windows.count)
        XCTAssertEqual(firstWindowUUID, subject.activeWindow)

        // Close the first window
        subject.windowDidClose(uuid: firstWindowUUID)

        // Check that the second window is now the only window
        XCTAssertEqual(1, subject.windows.count)
        XCTAssertEqual(secondWindowUUID, subject.windows.keys.first!)
        // Check that the second window is now automatically our "active" window
        XCTAssertEqual(secondWindowUUID, subject.activeWindow)
    }

    func testNextAvailableUUIDWhenNoTabDataIsSaved() {
        let subject = createSubject()
        let tabDataStore: TabDataStore = AppContainer.shared.resolve()
        let mockTabDataStore = tabDataStore as! MockTabDataStore
        mockTabDataStore.resetMockTabWindowUUIDs()

        // Check that asking for two UUIDs results in two unique/random UUIDs
        // Note: there is a possibility of collision between any two randomly-
        // generated UUIDs but it is astronomically small (1 out of 2^122).
        let uuid1 = subject.nextAvailableWindowUUID()
        let uuid2 = subject.nextAvailableWindowUUID()
        XCTAssertNotEqual(uuid1, uuid2)
    }

    func testNextAvailableUUIDWhenOnlyOneWindowSaved() {
        let subject = createSubject()
        let tabDataStore: TabDataStore = AppContainer.shared.resolve()
        let mockTabDataStore = tabDataStore as! MockTabDataStore
        mockTabDataStore.resetMockTabWindowUUIDs()

        let savedUUID = UUID()
        mockTabDataStore.injectMockTabWindowUUID(savedUUID)

        // Check that asking for first UUID returns the expected UUID
        XCTAssertEqual(savedUUID, subject.nextAvailableWindowUUID())
        // Open a window using this UUID
        subject.newBrowserWindowConfigured(AppWindowInfo(), uuid: savedUUID)
        // Check that asking for another UUID returns a new, random UUID
        XCTAssertNotEqual(savedUUID, subject.nextAvailableWindowUUID())
    }

    func testNextAvailableUUIDWhenMultipleWindowsSaved() {
        let subject = createSubject()
        let tabDataStore: TabDataStore = AppContainer.shared.resolve()
        let mockTabDataStore = tabDataStore as! MockTabDataStore
        mockTabDataStore.resetMockTabWindowUUIDs()

        let uuid1 = UUID()
        let uuid2 = UUID()
        let expectedUUIDs = Set<UUID>([uuid1, uuid2])
        mockTabDataStore.injectMockTabWindowUUID(uuid1)
        mockTabDataStore.injectMockTabWindowUUID(uuid2)

        // Ask for UUIDs for two windows, which we open and configure
        let result1 = subject.nextAvailableWindowUUID()
        subject.newBrowserWindowConfigured(AppWindowInfo(), uuid: result1)
        let result2 = subject.nextAvailableWindowUUID()
        subject.newBrowserWindowConfigured(AppWindowInfo(), uuid: result2)

        // Check that our UUIDs are the ones we expected
        // (Note: currently the order is undefined, this may be changing soon)
        XCTAssert(expectedUUIDs.contains(result1))
        XCTAssert(expectedUUIDs.contains(result2))
        XCTAssertEqual(expectedUUIDs.count, 2)

        // Check that asking for a 3rd UUID returns a new, random UUID
        let result3 = subject.nextAvailableWindowUUID()
        XCTAssertFalse(expectedUUIDs.contains(result3))
        XCTAssertNotEqual(result1, result3)
        XCTAssertNotEqual(result2, result3)
    }

    // MARK: - Test Subject

    private func createSubject() -> WindowManager {
        // For this test case, we create a new WindowManager that we can
        // modify and reset between each test case as needed, without
        // impacting other tests that may use the shared AppContainer.
        return WindowManagerImplementation()
    }
}
