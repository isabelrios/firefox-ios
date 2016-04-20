/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import XCTest
@testable import Client

class MenuTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testMenuConfigurationForBrowser() {
        var tabState = TabState(isPrivate: false, desktopSite: false, isBookmarked: false, url: NSURL(string: "http://mozilla.com")!, title: "Mozilla", favicon: nil)
        var browserConfiguration = AppMenuConfiguration(appState: .Tab(tabState: tabState))
        XCTAssertEqual(browserConfiguration.menuItems.count, 6)
        XCTAssertEqual(browserConfiguration.menuItems[0].title, AppMenuConfiguration.FindInPageTitleString)
        XCTAssertEqual(browserConfiguration.menuItems[1].title, AppMenuConfiguration.ViewDesktopSiteTitleString)
        XCTAssertEqual(browserConfiguration.menuItems[2].title, AppMenuConfiguration.SettingsTitleString)
        XCTAssertEqual(browserConfiguration.menuItems[3].title, AppMenuConfiguration.NewTabTitleString)
        XCTAssertEqual(browserConfiguration.menuItems[4].title, AppMenuConfiguration.NewPrivateTabTitleString)
        XCTAssertEqual(browserConfiguration.menuItems[5].title, AppMenuConfiguration.AddBookmarkTitleString)


        XCTAssertNotNil(browserConfiguration.menuToolbarItems)
        XCTAssertEqual(browserConfiguration.menuToolbarItems!.count, 4)
        XCTAssertEqual(browserConfiguration.menuToolbarItems![0].title, AppMenuConfiguration.TopSitesTitleString)
        XCTAssertEqual(browserConfiguration.menuToolbarItems![1].title, AppMenuConfiguration.BookmarksTitleString)
        XCTAssertEqual(browserConfiguration.menuToolbarItems![2].title, AppMenuConfiguration.HistoryTitleString)
        XCTAssertEqual(browserConfiguration.menuToolbarItems![3].title, AppMenuConfiguration.ReadingListTitleString)


        tabState = TabState(isPrivate: true, desktopSite: true, isBookmarked: true, url: NSURL(string: "http://mozilla.com")!, title: "Mozilla", favicon: nil)
        browserConfiguration = AppMenuConfiguration(appState: .Tab(tabState: tabState))
        XCTAssertEqual(browserConfiguration.menuItems.count, 6)
        XCTAssertEqual(browserConfiguration.menuItems[0].title, AppMenuConfiguration.FindInPageTitleString)
        XCTAssertEqual(browserConfiguration.menuItems[1].title, AppMenuConfiguration.ViewMobileSiteTitleString)
        XCTAssertEqual(browserConfiguration.menuItems[2].title, AppMenuConfiguration.SettingsTitleString)
        XCTAssertEqual(browserConfiguration.menuItems[3].title, AppMenuConfiguration.NewTabTitleString)
        XCTAssertEqual(browserConfiguration.menuItems[4].title, AppMenuConfiguration.NewPrivateTabTitleString)
        XCTAssertEqual(browserConfiguration.menuItems[5].title, AppMenuConfiguration.RemoveBookmarkTitleString)


        XCTAssertNotNil(browserConfiguration.menuToolbarItems)
        XCTAssertEqual(browserConfiguration.menuToolbarItems!.count, 4)
        XCTAssertEqual(browserConfiguration.menuToolbarItems![0].title, AppMenuConfiguration.TopSitesTitleString)
        XCTAssertEqual(browserConfiguration.menuToolbarItems![1].title, AppMenuConfiguration.BookmarksTitleString)
        XCTAssertEqual(browserConfiguration.menuToolbarItems![2].title, AppMenuConfiguration.HistoryTitleString)
        XCTAssertEqual(browserConfiguration.menuToolbarItems![3].title, AppMenuConfiguration.ReadingListTitleString)
    }

    func testMenuConfigurationForHomePanels() {
        let homePanelState = HomePanelState(isPrivate: false, selectedIndex: 0)
        let homePanelConfiguration = AppMenuConfiguration(appState: .HomePanels(homePanelState: homePanelState))
        XCTAssertEqual(homePanelConfiguration.menuItems.count, 3)
        XCTAssertEqual(homePanelConfiguration.menuItems[0].title, AppMenuConfiguration.NewTabTitleString)
        XCTAssertEqual(homePanelConfiguration.menuItems[1].title, AppMenuConfiguration.NewPrivateTabTitleString)
        XCTAssertEqual(homePanelConfiguration.menuItems[2].title, AppMenuConfiguration.SettingsTitleString)

        XCTAssertNil(homePanelConfiguration.menuToolbarItems)
    }

    func testMenuConfigurationForTabTray() {
        let tabTrayState = TabTrayState(isPrivate: false)
        let tabTrayConfiguration = AppMenuConfiguration(appState: .TabTray(tabTrayState: tabTrayState))
        XCTAssertEqual(tabTrayConfiguration.menuItems.count, 4)
        XCTAssertEqual(tabTrayConfiguration.menuItems[0].title, AppMenuConfiguration.NewTabTitleString)
        XCTAssertEqual(tabTrayConfiguration.menuItems[1].title, AppMenuConfiguration.NewPrivateTabTitleString)
        XCTAssertEqual(tabTrayConfiguration.menuItems[2].title, AppMenuConfiguration.CloseAllTabsTitleString)
        XCTAssertEqual(tabTrayConfiguration.menuItems[3].title, AppMenuConfiguration.SettingsTitleString)

        XCTAssertNotNil(tabTrayConfiguration.menuToolbarItems)
        XCTAssertEqual(tabTrayConfiguration.menuToolbarItems!.count, 4)
        XCTAssertEqual(tabTrayConfiguration.menuToolbarItems![0].title, AppMenuConfiguration.TopSitesTitleString)
        XCTAssertEqual(tabTrayConfiguration.menuToolbarItems![1].title, AppMenuConfiguration.BookmarksTitleString)
        XCTAssertEqual(tabTrayConfiguration.menuToolbarItems![2].title, AppMenuConfiguration.HistoryTitleString)
        XCTAssertEqual(tabTrayConfiguration.menuToolbarItems![3].title, AppMenuConfiguration.ReadingListTitleString)
    }

}
