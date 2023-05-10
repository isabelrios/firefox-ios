// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import XCTest
import Common
import Storage
@testable import Client

class CreditCardInputViewModelTests: XCTestCase {
    private var profile: MockProfile!
    private var viewModel: CreditCardInputViewModel!
    private var files: FileAccessor!
    private var autofill: RustAutofill!
    private var encryptionKey: String!

    override func setUp() {
        super.setUp()
        files = MockFiles()

        if let rootDirectory = try? files.getAndEnsureDirectory() {
            let databasePath = URL(fileURLWithPath: rootDirectory, isDirectory: true)
                .appendingPathComponent("testAutofill.db").path
            try? files.remove("testAutofill.db")

            if let key = try? createAutofillKey() {
                encryptionKey = key
            } else {
                XCTFail("Encryption key wasn't created")
            }

            autofill = RustAutofill(databasePath: databasePath)
            _ = autofill.reopenIfClosed()
        } else {
            XCTFail("Could not retrieve root directory")
        }

        profile = MockProfile()
        _ = profile.autofill.reopenIfClosed()
        viewModel = CreditCardInputViewModel(profile: profile)
    }

    override func tearDown() {
        super.tearDown()
        viewModel = nil
        profile = nil
    }

    func testEditViewModel_SavingCard() {
        viewModel.nameOnCard = "Ashton Mealy"
        viewModel.cardNumber = "4268811063712243"
        viewModel.expirationDate = "1288"
        let expectation = expectation(description: "wait for credit card fields to be saved")
        viewModel.saveCreditCard { creditCard, error in
            guard error == nil, let creditCard = creditCard else {
                XCTAssertTrue(false)
                return
            }
            XCTAssertEqual(creditCard.ccName, self.viewModel.nameOnCard)
            // Note: the number for credit card is encrypted so that part
            // will get added later and for now we will check the name only
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testEditState_setup() {
        // Setup edit state
        viewModel.state = .edit
        XCTAssertEqual(viewModel.state.leftBarBtn, .cancel)
        XCTAssertEqual(viewModel.state.rightBarBtn, .save)
        XCTAssertEqual(viewModel.state.title, .CreditCard.EditCard.EditCreditCardTitle)
        XCTAssertEqual(viewModel.state.rightBarBtn.title, .CreditCard.EditCard.SaveNavBarButtonLabel)
    }

    func testAddState_setup() {
        // Setup add state
        viewModel.state = .add
        XCTAssertEqual(viewModel.state.leftBarBtn, .close)
        XCTAssertEqual(viewModel.state.rightBarBtn, .save)
        XCTAssertEqual(viewModel.state.title, .CreditCard.EditCard.AddCreditCardTitle)
        XCTAssertEqual(viewModel.state.rightBarBtn.title, .CreditCard.EditCard.SaveNavBarButtonLabel)
    }

    func testViewState_setup() {
        // Setup view state
        viewModel.state = .view
        XCTAssertEqual(viewModel.state.leftBarBtn, .close)
        XCTAssertEqual(viewModel.state.rightBarBtn, .edit)
        XCTAssertEqual(viewModel.state.title, .CreditCard.EditCard.ViewCreditCardTitle)
        XCTAssertEqual(viewModel.state.rightBarBtn.title, .CreditCard.EditCard.EditNavBarButtonLabel)
    }

    func testRightBarButtonNotEnabledEdit() {
        viewModel.state = .edit
        viewModel.nameOnCard = "Kenny Champion"
        viewModel.expirationDate = "123"
        viewModel.cardNumber = "4871007782167426"
        XCTAssertFalse(viewModel.isRightBarButtonEnabled)
    }

    func testRightBarButtonEnabledEdit() {
        viewModel.state = .edit
        viewModel.nameOnCard = "Kenny Champion"
        viewModel.expirationDate = "1239"
        viewModel.cardNumber = "4871007782167426"
        XCTAssert(viewModel.isRightBarButtonEnabled)
    }

    func testRightBarButtonNotEnabledAdd() {
        viewModel.state = .add
        viewModel.nameOnCard = "Jakyla Labarge"
        viewModel.expirationDate = "123"
        viewModel.cardNumber = "4717219604213696"
        XCTAssertFalse(viewModel.isRightBarButtonEnabled)
    }

    func testRightBarButtonEnabledAdd() {
        viewModel.state = .add
        viewModel.nameOnCard = "Jakyla Labarge"
        viewModel.expirationDate = "1239"
        viewModel.cardNumber = "4717219604213696"
        XCTAssert(viewModel.isRightBarButtonEnabled)
    }

    func testRightBarButtonDisabled_AddState() {
        rightBarButtonDisabled_Empty_CardName(state: .add)
        rightBarButtonDisabled_Empty_CardName_Expiration(state: .add)
        rightBarButtonDisabled_Empty_CardName_Expiration_Number(state: .add)
    }

    func testRightBarButtonDisabled_EditState() {
        rightBarButtonDisabled_Empty_CardName(state: .edit)
        rightBarButtonDisabled_Empty_CardName_Expiration(state: .edit)
        rightBarButtonDisabled_Empty_CardName_Expiration_Number(state: .edit)
    }

    func testGetCopyValueForNumber() {
        viewModel.nameOnCard = "Jakyla Labarge"
        viewModel.expirationDate = "12 / 39"
        viewModel.cardNumber = "4717219604213696"

        let result = viewModel.getCopyValueFor(.number)
        XCTAssertEqual(result, "4717219604213696")
    }

    func testGetCopyValueForName() {
        viewModel.nameOnCard = "Jakyla Labarge"
        viewModel.expirationDate = "12 / 39"
        viewModel.cardNumber = "4717219604213696"

        let result = viewModel.getCopyValueFor(.name)
        XCTAssertEqual(result, "Jakyla Labarge")
    }

    func testGetCopyValueForExpiration() {
        viewModel.nameOnCard = "Jakyla Labarge"
        viewModel.expirationDate = "12 / 39"
        viewModel.cardNumber = "4717219604213696"

        let result = viewModel.getCopyValueFor(.expiration)
        XCTAssertEqual(result, "1239")
    }

    func testClearValues() {
        viewModel.nameOnCard = "Jakyla Labarge"
        viewModel.expirationDate = "12 / 39"
        viewModel.cardNumber = "4717219604213696"
        viewModel.nameIsValid = false
        viewModel.expirationIsValid = false
        viewModel.numberIsValid = false
        viewModel.creditCard = CreditCard(guid: "1",
                                          ccName: "Allen Burges",
                                          ccNumberEnc: "1234567891234567",
                                          ccNumberLast4: "4567",
                                          ccExpMonth: 1234567,
                                          ccExpYear: 2023,
                                          ccType: "VISA",
                                          timeCreated: 1234678,
                                          timeLastUsed: nil,
                                          timeLastModified: 123123,
                                          timesUsed: 123123)

        viewModel.clearValues()

        XCTAssert(viewModel.nameOnCard.isEmpty)
        XCTAssert(viewModel.cardNumber.isEmpty)
        XCTAssert(viewModel.expirationDate.isEmpty)
        XCTAssert(viewModel.nameIsValid)
        XCTAssert(viewModel.expirationIsValid)
        XCTAssert(viewModel.numberIsValid)
        XCTAssertNil(viewModel.creditCard)
    }

    // MARK: Helpers

    func rightBarButtonDisabled_Empty_CardName(
        state: CreditCardEditState) {
        guard state == .edit || state == .add else { return }
        viewModel.state = state
        viewModel.nameOnCard = ""
        viewModel.expirationDate = "123"
        viewModel.cardNumber = "4717219604213696"
        XCTAssertTrue(!viewModel.isRightBarButtonEnabled)
    }

    func rightBarButtonDisabled_Empty_CardName_Expiration(
        state: CreditCardEditState) {
        guard state == .edit || state == .add else { return }
        viewModel.state = state
        viewModel.nameOnCard = ""
        viewModel.expirationDate = ""
        viewModel.cardNumber = "4717219604213696"
        XCTAssertTrue(!viewModel.isRightBarButtonEnabled)
    }

    func rightBarButtonDisabled_Empty_CardName_Expiration_Number(
        state: CreditCardEditState) {
        guard state == .edit || state == .add else { return }
        viewModel.state = state
        viewModel.nameOnCard = ""
        viewModel.expirationDate = ""
        viewModel.cardNumber = ""
        XCTAssertTrue(!viewModel.isRightBarButtonEnabled)
    }
}
