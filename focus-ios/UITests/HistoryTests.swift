/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit

class HistoryTests: KIFTestCase {
    private var webRoot: String!

    override func setUp() {
        webRoot = SimplePageServer.start()
    }

    func addHistoryItemPage(pageNo: Int) -> String {
        // Load a page
        tester().tapViewWithAccessibilityIdentifier("url")
        let url = "\(webRoot)/numberedPage.html?page=\(pageNo)"
        tester().clearTextFromAndThenEnterTextIntoCurrentFirstResponder("\(url)\n")
        tester().waitForWebViewElementWithAccessibilityLabel("Page \(pageNo)")
        return "Page \(pageNo), \(url)"
    }

    func addHistoryItems(noOfItemsToAdd: Int) -> [String] {
        var urls = [String]()
        for index in 1...noOfItemsToAdd {
            urls.append(addHistoryItemPage(index))
        }

        return urls
    }

    /**
     * Tests for listed history visits
     */
    func testHistoryUI() {

        let urls = addHistoryItems(2)

        // Check that both appear in the history home panel
        tester().tapViewWithAccessibilityIdentifier("url")
        tester().tapViewWithAccessibilityLabel("History")

        let firstHistoryRow = tester().waitForViewWithAccessibilityLabel(urls[0]) as! UITableViewCell
        XCTAssertNotNil(firstHistoryRow.imageView?.image)
        let secondHistoryRow = tester().waitForViewWithAccessibilityLabel(urls[1]) as! UITableViewCell
        XCTAssertNotNil(secondHistoryRow.imageView?.image)

        tester().tapViewWithAccessibilityLabel("Cancel")
    }

    func testDeleteHistoryItemFromSmallList() {
        // add 2 history items
        // delete all history items

        let urls = addHistoryItems(2)

        // Check that both appear in the history home panel
        tester().tapViewWithAccessibilityIdentifier("url")
        tester().tapViewWithAccessibilityLabel("History")

        tester().swipeViewWithAccessibilityLabel(urls[0], inDirection: KIFSwipeDirection.Left)
        tester().tapViewWithAccessibilityLabel("Remove")

        let secondHistoryRow = tester().waitForViewWithAccessibilityLabel(urls[1]) as! UITableViewCell
        XCTAssertNotNil(secondHistoryRow.imageView?.image)

        if let keyWindow = UIApplication.sharedApplication().keyWindow {
            XCTAssertNil(keyWindow.accessibilityElementWithLabel(urls[0]), "page 1 should have been deleted")
        }

        tester().tapViewWithAccessibilityLabel("Cancel")
    }

    func testDeleteHistoryItemFromLargeList() {
        for pageNo in 1...102 {
            BrowserUtils.addHistoryEntry("Page \(pageNo)", url: NSURL(string: "\(webRoot)/numberedPage.html?page=\(pageNo)")!)
        }
        let urlToDelete = "Page \(102), \(webRoot)/numberedPage.html?page=\(102)"
        let secondToLastUrl = "Page \(101), \(webRoot)/numberedPage.html?page=\(101)"

        tester().tapViewWithAccessibilityLabel("History")

        let firstHistoryRow = tester().waitForViewWithAccessibilityLabel(urlToDelete) as! UITableViewCell
        tester().swipeViewWithAccessibilityLabel(urlToDelete, inDirection: KIFSwipeDirection.Left)
        tester().tapViewWithAccessibilityLabel("Remove")

        let secondHistoryRow = tester().waitForViewWithAccessibilityLabel(secondToLastUrl) as! UITableViewCell
        XCTAssertNotNil(secondHistoryRow.imageView?.image)

        if let keyWindow = UIApplication.sharedApplication().keyWindow {
            XCTAssertNil(keyWindow.accessibilityElementWithLabel(urlToDelete), "page 102 should have been deleted")
        }
    }

    override func tearDown() {
        BrowserUtils.resetToAboutHome(tester())
    }
}
