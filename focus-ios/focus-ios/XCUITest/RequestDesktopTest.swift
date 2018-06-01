/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import XCTest

class RequestDesktopTest: BaseTestCase {
        
    override func setUp() {
        super.setUp()
        dismissFirstRunUI()
    }
    
    override func tearDown() {
        app.terminate()
        super.tearDown()
    }
    
    func testLongPressReloadButton() {
        let urlBarTextField = app.textFields["URLBar.urlText"]
        
        // Wait for existence rather than hittable because the textfield is technically disabled
        waitforExistence(element: urlBarTextField)
        app.textFields["URLBar.urlText"].tap()
        app.typeText("facebook.com\n")
        
        waitforExistence(element:  app.buttons["BrowserToolset.stopReloadButton"])
        app.buttons["BrowserToolset.stopReloadButton"].press(forDuration: 1.0)
        
        waitforHittable(element: app.sheets.buttons["Request Desktop Site"])
        app.sheets.buttons["Request Desktop Site"].tap()
        
        waitForWebPageLoad()
        
        guard let text = urlBarTextField.value as? String else {
            XCTFail()
            return
        }
        
        if text.contains("m.facebook") {
            XCTFail()
        }
    }
    
    func testActivityMenuRequestDesktopItem(){
        let urlBarTextField = app.textFields["URLBar.urlText"]
        
        // Wait for existence rather than hittable because the textfield is technically disabled
        waitforExistence(element: urlBarTextField)
        app.textFields["URLBar.urlText"].tap()
        app.typeText("facebook.com\n")
        
        waitforExistence(element:  app.buttons["BrowserToolset.sendButton"])
        app.buttons["BrowserToolset.sendButton"].tap()
        
        waitforHittable(element: app.buttons["Request Desktop Site"])
        app.buttons["Request Desktop Site"].tap()
        
        waitForWebPageLoad()
        
        guard let text = urlBarTextField.value as? String else {
            XCTFail()
            return
        }
        
        if text.contains("m.facebook") {
            XCTFail()
        }
    }
}
