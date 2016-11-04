/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

class ErrorPage {
    let error: NSError

    init(error: Error) {
        self.error = error as NSError
    }

    lazy var file: String = {
        var file: String!

        DispatchQueue.main.sync {
            file = Bundle.main.path(forResource: "errorPage", ofType: "html")!
        }

        return file
    }()

    var data: Data {
        let page = try! String(contentsOfFile: file)
            .replacingOccurrences(of: "%messageLong%", with: error.localizedDescription)
            .replacingOccurrences(of: "%messageShort%", with: error.domain)
            .replacingOccurrences(of: "%button%", with: UIConstants.strings.errorTryAgain)
        return page.data(using: .utf8)!
    }
}
