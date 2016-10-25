/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
@testable import Storage
@testable import Client

// This test is only for devices that does not have Panel implementation (e.g. iPad):
// https://github.com/mozilla-mobile/firefox-ios/blob/master/Client/Frontend/Home/HomePanels.swift#L23
// When running on iPhone, this test will fail, because the Collectionview does not have an identifier, and 
// the deletion method is different
class TopSitesTests: KIFTestCase {
    private var webRoot: String!
    private var profile: Profile!

    override func setUp() {
        profile = (UIApplication.sharedApplication().delegate as! AppDelegate).profile!
        profile.prefs.setObject([], forKey: "topSites.deletedSuggestedSites")
        webRoot = SimplePageServer.start()
        BrowserUtils.dismissFirstRunUI(tester())
    }

    private func extractTextSizeFromThumbnail(thumbnail: ThumbnailCell) -> CGFloat? {
        return thumbnail.textLabel.font.pointSize
    }

    private func accessibilityLabelsForAllTopSites(collection: UICollectionView) -> [String] {
        return collection.visibleCells().reduce([], combine: { arr, cell in
            if let label = cell.accessibilityLabel {
                return arr + [label]
            }
            return arr
        })
    }

/*
    func testChangingDyamicFontOnTopSites() {
        DynamicFontUtils.restoreDynamicFontSize(tester())

        let collection = tester().waitForViewWithAccessibilityIdentifier("Top Sites View") as! UICollectionView
        let thumbnail = collection.visibleCells().first as! ThumbnailCell

        let size = extractTextSizeFromThumbnail(thumbnail)

        DynamicFontUtils.bumpDynamicFontSize(tester())
        let bigSize = extractTextSizeFromThumbnail(thumbnail)

        DynamicFontUtils.lowerDynamicFontSize(tester())
        let smallSize = extractTextSizeFromThumbnail(thumbnail)

        XCTAssertGreaterThan(bigSize!, size!)
        XCTAssertGreaterThanOrEqual(size!, smallSize!)
    }
*/
    func testRemovingSite() {
        // Switch to the Bookmarks panel so we can later reload Top Sites.
        tester().tapViewWithAccessibilityLabel("Bookmarks")

        // Load a set of dummy domains.
        for i in 1...10 {
            BrowserUtils.addHistoryEntry("", url: NSURL(string: "https://test\(i).com")!)
        }

        // Switch back to the Top Sites panel.
        tester().tapViewWithAccessibilityLabel("Top sites")

        // Remove the first site and verify that all other sites shift to replace it.
        let collection = tester().waitForViewWithAccessibilityIdentifier("Top Sites View") as! UICollectionView

        // Get the first cell (test10.com).
        let cell = collection.cellForItemAtIndexPath(NSIndexPath(forItem: 0, inSection: 0))!

        let cellToDeleteLabel = cell.accessibilityLabel
        tester().longPressViewWithAccessibilityLabel(cellToDeleteLabel, duration: 1)
        tester().waitForViewWithAccessibilityLabel("Remove page - \(cellToDeleteLabel!)")
        cell.tapAtPoint(CGPointZero)

        // Close editing mode.
        tester().tapViewWithAccessibilityLabel("Done")
        tester().waitForAbsenceOfViewWithAccessibilityLabel("Remove page")

        let postDeletedLabels = accessibilityLabelsForAllTopSites(collection)
        XCTAssertFalse(postDeletedLabels.contains(cellToDeleteLabel!))
    }

    func testRemovingSuggestedSites() {
        // Switch to the Bookmarks panel so we can later reload Top Sites.
        tester().tapViewWithAccessibilityLabel("Bookmarks")
        tester().tapViewWithAccessibilityLabel("Top sites")

        var collection = tester().waitForViewWithAccessibilityIdentifier("Top Sites View") as! UICollectionView
        let firstCell = collection.cellForItemAtIndexPath(NSIndexPath(forItem: 0, inSection: 0))!
        let cellToDeleteLabel = firstCell.accessibilityLabel
        tester().longPressViewWithAccessibilityLabel(cellToDeleteLabel, duration: 1)
        tester().tapViewWithAccessibilityLabel("Remove page - \(cellToDeleteLabel!)")
        tester().waitForAnimationsToFinish()

        // Close editing mode
        tester().tapViewWithAccessibilityLabel("Done")

        // Verify that the tile we removed is removed

        collection = tester().waitForViewWithAccessibilityIdentifier("Top Sites View") as! UICollectionView
        XCTAssertFalse(accessibilityLabelsForAllTopSites(collection).contains(cellToDeleteLabel!))
    }

  // Disabled since deleted sites reappear during automation.  Manually this is not reproducible.  Seems to be the KIFTest update issue
    /*
    func testEmptyState() {
        // Delete all of the suggested tiles
        var collection = tester().waitForViewWithAccessibilityIdentifier("Top Sites View") as! UICollectionView
        while collection.visibleCells().count > 0 {
            let firstCell = collection.visibleCells().first!
            firstCell.longPressAtPoint(CGPointZero, duration: 3)
            tester().tapViewWithAccessibilityLabel("Remove page - \(firstCell.accessibilityLabel!)")
            tester().waitForAnimationsToFinish()
        }

        // Close editing mode
        tester().tapViewWithAccessibilityLabel("Done")

        // Check for empty state
        XCTAssertTrue(tester().viewExistsWithLabel("Welcome to Top Sites"))

        // Add a new history item

        // Verify that empty state no longer appears
        //BrowserUtils.addHistoryEntry("", url: NSURL(string: "https://mozilla.org")!)

        tester().tapViewWithAccessibilityLabel("Bookmarks")
        tester().tapViewWithAccessibilityLabel("Top sites")
        tester().waitForAnimationsToFinish()

        collection = tester().waitForViewWithAccessibilityIdentifier("Top Sites View") as! UICollectionView
        // 4 default topsites are re-populated
        XCTAssertEqual(collection.visibleCells().count, 1)
        XCTAssertFalse(tester().viewExistsWithLabel("Welcome to Top Sites"))
    }
*/
    override func tearDown() {
        //DynamicFontUtils.restoreDynamicFontSize(tester())
        BrowserUtils.resetToAboutHome(tester())
        BrowserUtils.clearPrivateData(tester: tester())
    }
}
