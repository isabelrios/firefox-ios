// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest
import WebKit
@testable import Client

final class FakespotCoordinatorTests: XCTestCase {
    private var mockRouter: MockRouter!
    let exampleProduct = URL(string: "https://www.amazon.com/Under-Armour-Charged-Assert-Running/dp/B087T8Q2C4")!

    override func setUp() {
        super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        self.mockRouter = MockRouter(navigationController: MockNavigationController())
    }

    override func tearDown() {
        super.tearDown()
        self.mockRouter = nil
        AppContainer.shared.reset()
    }

    func testInitialState() {
        let subject = createSubject()

        XCTAssertTrue(subject.childCoordinators.isEmpty)
        XCTAssertEqual(mockRouter.setRootViewControllerCalled, 0)
    }

    func testFakespotStarts_presentsFakespotController() throws {
        let subject = createSubject()

        subject.start(productURL: exampleProduct)

        XCTAssertEqual(mockRouter.presentCalled, 1)
        XCTAssertTrue(mockRouter.presentedViewController is FakespotViewController)
    }

    func testFakespotCoordinatorDelegate_didDidDismiss_callsRouterDismiss() throws {
        let subject = createSubject()

        subject.start(productURL: exampleProduct)
        subject.fakespotControllerDidDismiss()

        XCTAssertEqual(mockRouter.dismissCalled, 1)
        XCTAssertTrue(subject.childCoordinators.isEmpty)
    }

    // MARK: - Helpers
    private func createSubject(file: StaticString = #file,
                               line: UInt = #line) -> FakespotCoordinator {
        let subject = FakespotCoordinator(router: mockRouter)

        trackForMemoryLeaks(subject, file: file, line: line)
        return subject
    }
}
