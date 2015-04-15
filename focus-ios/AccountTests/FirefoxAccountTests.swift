/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import UIKit
import XCTest

class FirefoxAccountTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSerialization() {
        let d: [String: AnyObject] = [
            "version": 1,
            "email": "testtest@test.com",
            "uid": "uid",
            "authEndpoint": "https://test.com/auth",
            "contentEndpoint": "https://test.com/content",
            "oauthEndpoint": "https://test.com/oauth"
        ]

        let account1 = FirefoxAccount(
                email: d["email"] as! String,
                uid: d["uid"] as! String,
                authEndpoint: NSURL(string: d["authEndpoint"] as! String)!,
                contentEndpoint: NSURL(string: d["contentEndpoint"] as! String)!,
                oauthEndpoint: NSURL(string: d["oauthEndpoint"] as! String)!,
                stateKeyLabel: Bytes.generateGUID(),
                state: SeparatedState())
        let d1 = account1.asDictionary()

        let account2 = FirefoxAccount.fromDictionary(d1)
        XCTAssertNotNil(account2)
        let d2 = account2!.asDictionary()

        for (k, v) in d {
            // Skip version, which is an Int.
            if let s = v as? String {
                XCTAssertEqual(s, d1[k] as! String, "Value for '\(k)' does not agree for manually created account.")
                XCTAssertEqual(s, d2[k] as! String, "Value for '\(k)' does not agree for deserialized account.")
            }
        }
    }
}
