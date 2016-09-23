import Foundation
import XCTest
import Storage
import WebImage
@testable import Client
import Shared

class TestFavicons: ProfileTest {

    private func addSite(favicons: Favicons, url: String, s: Bool = true) {
        let expectation = self.expectationWithDescription("Wait for history")
        let site = Site(url: url, title: "")
        let icon = Favicon(url: url + "/icon.png", type: IconType.Icon)
        favicons.addFavicon(icon, forSite: site).upon {
            XCTAssertEqual($0.isSuccess, s, "Icon added \(url)")
            expectation.fulfill()
        }
        self.waitForExpectationsWithTimeout(100, handler: nil)
    }

    func testFaviconFetcherParse() {
        let expectation = self.expectationWithDescription("Wait for Favicons to be fetched")

        let profile = MockProfile()
        // I want a site that also has an iOS app so I can get "apple-touch-icon-precomposed" icons as well
        let url = NSURL(string: "https://instagram.com")
        FaviconFetcher.getForURL(url!, profile: profile).uponQueue(dispatch_get_main_queue()) { result in
            guard let favicons = result.successValue where favicons.count > 0, let url = favicons.first?.url.asURL else {
                XCTFail("Favicons were not found.")
                return expectation.fulfill()
            }
            XCTAssertGreaterThan(favicons.count, 1, "Instagram should have more than one Favicon.")
            SDWebImageManager.sharedManager().downloadImageWithURL(url, options: SDWebImageOptions.RetryFailed, progress: nil, completed: { (img, err, cache, finished, url) in
                guard let image: UIImage = img else {
                    XCTFail("Not a valid URL provided for a favicon.")
                    return expectation.fulfill()
                }
                XCTAssertNotEqual(image.size, CGSize(width: 0, height: 0))
                expectation.fulfill()
            })

        }
        self.waitForExpectationsWithTimeout(3000, handler: nil)
    }

    // TODO: uncomment.
    /*
    private func checkSites(favicons: Favicons, icons: [String], s: Bool = true) {
        let expectation = self.expectationWithDescription("Wait for history")

        // Retrieve the entry
        let opts: QueryOptions? = nil
        favicons.get(opts, complete: { cursor in
            XCTAssertEqual(cursor.status, CursorStatus.Success, "returned success \(cursor.statusMessage)")
            XCTAssertEqual(cursor.count, icons.count, "cursor has \(icons.count) entries")

            for index in 0..<cursor.count {
                let (site, favicon) = cursor[index]!
                XCTAssertNotNil(s, "cursor has a favicon for entry")
                let index = find(icons, favicon.url)
                XCTAssertNotNil(index, "Found expected entry \(favicon.url)")
            }
            expectation.fulfill()
        })

        self.waitForExpectationsWithTimeout(100, handler: nil)
    }

    private func clear(favicons: Favicons, s: Bool = true) {
        let expectation = self.expectationWithDescription("Wait for history")

        let opts: QueryOptions? = nil
        favicons.clear(opts) { (success) -> Void in
            XCTAssertEqual(s, success, "Sites cleared")
            expectation.fulfill()
        }

        self.waitForExpectationsWithTimeout(100, handler: nil)
    }

    // This is a very basic test. Adds an entry. Retrieves it, and then clears the database
    func testFavicons() {
        withTestProfile { profile -> Void in
            let h = profile.favicons
            self.addSite(h, url: "url1")
            self.addSite(h, url: "url1")
            self.addSite(h, url: "url1")
            self.addSite(h, url: "url2")
            self.addSite(h, url: "url2")
            self.checkSites(h, icons: ["url1/icon.png", "url2/icon.png"], s: true)

            // TODO: Use the local file server for URLs here, so that we can test download/save/delete of local storage
            self.clear(h)
            profile.files.remove("mock.db")
        }
    }
    */
}
