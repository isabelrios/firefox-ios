// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import Glean

@testable import Client

class GleanPlumbMessageManagerTests: XCTestCase {
    var subject: GleanPlumbMessageManager!
    var messagingStore: MockGleanPlumbMessageStore!
    var applicationHelper: MockApplicationHelper!
    let messageId = "testId"

    override func setUp() {
        super.setUp()

        Glean.shared.resetGlean(clearStores: true)
        Glean.shared.enableTestingMode()
        messagingStore = MockGleanPlumbMessageStore(messageId: messageId)
        applicationHelper = MockApplicationHelper()
        subject = GleanPlumbMessageManager(messagingStore: messagingStore, applicationHelper: applicationHelper)
    }

    override func tearDown() {
        super.tearDown()

        messagingStore = nil
        subject = nil
    }

    func testManagerHasMessage() {
        let messageForSurface = subject.hasMessage(for: .newTabCard)
        XCTAssertTrue(messageForSurface)
    }

    func testManagerGetMessage() {
        guard let message = subject.getNextMessage(for: .newTabCard) else {
            XCTFail("Expected to retrieve message")
            return
        }

        subject.onMessageDisplayed(message)
        testEventMetricRecordingSuccess(metric: GleanMetrics.Messaging.shown)
    }

    func testManagerOnMessageDisplayed() {
        let message = createMessage(messageId: messageId)
        subject.onMessageDisplayed(message)
        let messageMetadata = messagingStore.getMessageMetadata(messageId: messageId)
        XCTAssertFalse(messageMetadata.isExpired)
        XCTAssertEqual(messageMetadata.impressions, 1)
        testEventMetricRecordingSuccess(metric: GleanMetrics.Messaging.shown)
    }

    func testManagerOnMessagePressed() {
        let message = createMessage(messageId: messageId)
        subject.onMessagePressed(message)
        let messageMetadata = messagingStore.getMessageMetadata(messageId: messageId)
        XCTAssertTrue(messageMetadata.isExpired)
        XCTAssertEqual(applicationHelper.openURLCalled, 1)
        testEventMetricRecordingSuccess(metric: GleanMetrics.Messaging.clicked)
    }

    func testManagerOnMessagePressed_withWebpage() {
        let message = createMessage(messageId: messageId, action: "https://mozilla.com")
        subject.onMessagePressed(message)
        let messageMetadata = messagingStore.getMessageMetadata(messageId: messageId)
        XCTAssertTrue(messageMetadata.isExpired)
        XCTAssertEqual(applicationHelper.openURLCalled, 1)
        XCTAssertNotNil(applicationHelper.lastOpenURL)
        XCTAssertTrue(applicationHelper.lastOpenURL!.absoluteString.hasPrefix(URL.mozInternalScheme))
        testEventMetricRecordingSuccess(metric: GleanMetrics.Messaging.clicked)
    }

    func testManagerOnMessagePressed_withMalformedURL() {
        let message = createMessage(messageId: messageId, action: "http://www.google.com?q=א")
        subject.onMessagePressed(message)
        let messageMetadata = messagingStore.getMessageMetadata(messageId: messageId)
        XCTAssertTrue(messageMetadata.isExpired)
        XCTAssertEqual(applicationHelper.openURLCalled, 0)
        XCTAssertNil(applicationHelper.lastOpenURL)
        testEventMetricRecordingSuccess(metric: GleanMetrics.Messaging.malformed)
    }

    func testManagerOnMessageDismissed() {
        let message = createMessage(messageId: messageId)
        subject.onMessageDismissed(message)
        let messageMetadata = messagingStore.getMessageMetadata(messageId: messageId)
        XCTAssertEqual(messageMetadata.dismissals, 1)
        XCTAssertTrue(messageMetadata.isExpired)
        testEventMetricRecordingSuccess(metric: GleanMetrics.Messaging.dismissed)
    }

    // MARK: - Helper function

    private func createMessage(messageId: String,
                               action: String = "MAKE_DEFAULT_BROWSER") -> GleanPlumbMessage {
        let styleData = MockStyleData(priority: 50, maxDisplayCount: 3)

        let messageMetadata = GleanPlumbMessageMetaData(id: messageId,
                                                        impressions: 0,
                                                        dismissals: 0,
                                                        isExpired: false)
        return GleanPlumbMessage(id: messageId,
                                 data: MockMessageData(),
                                 action: action,
                                 triggers: ["ALWAYS"],
                                 style: styleData,
                                 metadata: messageMetadata)
    }
}

// MARK: - MockGleanPlumbMessageStore
class MockGleanPlumbMessageStore: GleanPlumbMessageStoreProtocol {
    private var metadata: GleanPlumbMessageMetaData
    var messageId: String

    var maxImpression = 3

    init(messageId: String) {
        self.messageId = messageId
        metadata = GleanPlumbMessageMetaData(id: messageId,
                                             impressions: 0,
                                             dismissals: 0,
                                             isExpired: false)
    }

    func getMessageMetadata(messageId: String) -> GleanPlumbMessageMetaData {
        return metadata
    }

    func onMessageDisplayed(_ message: GleanPlumbMessage) {
        metadata.impressions += 1

        if metadata.impressions > maxImpression {
            onMessageExpired(metadata, surface: message.data.surface, shouldReport: true)
        }
    }

    func onMessagePressed(_ message: GleanPlumbMessage) {
        onMessageExpired(metadata, surface: message.data.surface, shouldReport: false)
    }

    func onMessageDismissed(_ message: GleanPlumbMessage) {
        metadata.dismissals += 1
        onMessageExpired(metadata, surface: message.data.surface, shouldReport: false)
    }

    func onMessageExpired(_ message: GleanPlumbMessageMetaData, surface: MessageSurfaceId, shouldReport: Bool) {
        metadata.isExpired = true
    }
}
