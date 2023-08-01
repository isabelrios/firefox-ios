// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import Client

final class ShoppingProductTests: XCTestCase {
    var client: TestFakeSpotClient!

    override func setUp() {
        super.setUp()
        client = TestFakeSpotClient()
    }

    override func tearDown() {
        super.tearDown()
        client = nil
    }

    func testAmazonURL_returnsExpectedProduct() {
        let url = URL(string: "https://www.amazon.com/Under-Armour-Charged-Assert-Running/dp/B087T8Q2C4")!

        let sut = ShoppingProduct(url: url)
        let expected = Product(id: "B087T8Q2C4", host: "amazon.com", topLevelDomain: "com", sitename: "amazon")

        XCTAssertEqual(sut.product, expected)
    }

    func testBestBuyURL_returnsExpectedProduct() {
        let url = URL(string: "https://www.bestbuy.com/site/macbook-air-13-3-laptop-apple-m1-chip-8gb-memory-256gb-ssd-space-gray/5721600.p?skuId=5721600")!

        let sut = ShoppingProduct(url: url)
        let expected = Product(id: "5721600.p", host: "bestbuy.com", topLevelDomain: "com", sitename: "bestbuy")

        XCTAssertEqual(sut.product, expected)
    }

    func testBasicURL_returnsNilProduct() {
        let url = URL(string: "https://www.example.com")!

        let sut = ShoppingProduct(url: url)

        XCTAssertNil(sut.product)
    }

    func testBasicURL_hidesShoppingIcon() {
        let url = URL(string: "https://www.example.com")!

        let sut = ShoppingProduct(url: url)

        XCTAssertFalse(sut.isShoppingCartButtonVisible)
    }

    func testFetchingProductAnalysisData_WithInvalidURL_ReturnsNil() async throws {
        let url = URL(string: "https://www.example.com")!

        let sut = ShoppingProduct(url: url)
        let productData = try await sut.fetchProductAnalysisData()

        XCTAssertNil(productData)
    }

    func testFetchingProductAnalysisData_WithValidURL_CallsClientAPI() async throws {
        let url = URL(string: "https://www.amazon.com/Under-Armour-Charged-Assert-Running/dp/B087T8Q2C4")!

        let sut = ShoppingProduct(url: url, client: client)
        let productData = try await sut.fetchProductAnalysisData()

        XCTAssertNotNil(productData)
        XCTAssertTrue(client.fetchProductAnalysisDataCalled)
        XCTAssertEqual(client.productId, "B087T8Q2C4")
        XCTAssertEqual(client.website, "amazon.com")
    }

    func testFetchingProductAdData_WithInvalidURL_ReturnsEmptyArray() async throws {
        let url = URL(string: "https://www.example.com")!

        let sut = ShoppingProduct(url: url)
        let productAdData = try await sut.fetchProductAdsData()

        XCTAssertTrue(productAdData.isEmpty)
    }

    func testFetchingProductAdData_WithValidURL_CallsClientAPI() async throws {
        let url = URL(string: "https://www.amazon.com/Under-Armour-Charged-Assert-Running/dp/B087T8Q2C4")!

        let sut = ShoppingProduct(url: url, client: client)
        let productAdData = try await sut.fetchProductAdsData()

        XCTAssertNotNil(productAdData)
        XCTAssertTrue(client.fetchProductAdsDataCalled)
        XCTAssertEqual(client.productId, "B087T8Q2C4")
        XCTAssertEqual(client.website, "amazon.com")
    }
}

final class TestFakeSpotClient: FakeSpotClientType {
    var productId: String = ""
    var website: String = ""
    var fetchProductAnalysisDataCalled = false
    var fetchProductAdsDataCalled = false

    func fetchProductAnalysisData(productId: String, website: String) async throws -> ProductAnalysisData {
        self.productId = productId
        self.website = website
        self.fetchProductAnalysisDataCalled = true
        return .empty
    }

    func fetchProductAdData(productId: String, website: String) async throws -> [ProductAdsData] {
        self.productId = productId
        self.website = website
        self.fetchProductAdsDataCalled = true
        return []
    }
}

extension ProductAnalysisData {
    static let empty = ProductAnalysisData(
        productId: "",
        grade: "",
        adjustedRating: 0,
        needsAnalysis: false,
        analysisUrl: URL(string: "https://www.example.com")!,
        highlights: Highlights(price: [], quality: [], competitiveness: [])
    )
}
