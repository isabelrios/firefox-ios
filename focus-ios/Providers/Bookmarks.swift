// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Alamofire

class Bookmark {
    var title: String
    var url: String

    init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

class TestBookmarksProvder : Bookmarks {
    override func getAll(success: ([Bookmark]) -> (), error: (RequestError) -> ()) {
        var res = [Bookmark]()
        for i in 0...10 {
            var b = Bookmark(title: "Title \(i)", url: "http://www.example.com/\(i)")
            res.append(b)
        }
        success(res)
    }
}

class Bookmarks: NSObject {
    private let account: Account

    init(account: Account) {
        self.account = account
    }

    func getAll(success: ([Bookmark]) -> (), error: (RequestError) -> ()) {
        account.makeAuthRequest(
            "bookmarks/recent",
            success: { data in
                 success(self.parseResponse(data));
            },
            error: error)
    }

    private func parseResponse(response: AnyObject?) -> [Bookmark] {
        var resp : [Bookmark] = [];

        if let response: NSArray = response as? NSArray {
            for bookmark in response {
                var title: String = ""
                var url: String = ""

                if let t = bookmark.valueForKey("title") as? String {
                    title = t
                } else {
                    continue;
                }

                if let u = bookmark.valueForKey("bmkUri") as? String {
                    url = u
                } else {
                    continue;
                }

                resp.append(Bookmark(title: title, url: url))
            }
        }

        return resp;
    }
};
