/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Storage
import XCGLogger

private let log = Logger.syncLogger
private let TabsStorageVersion = 1

public class TabsSynchronizer: BaseSingleCollectionSynchronizer, Synchronizer {
    public required init(scratchpad: Scratchpad, delegate: SyncDelegate, basePrefs: Prefs) {
        super.init(scratchpad: scratchpad, delegate: delegate, basePrefs: basePrefs, collection: "tabs")
    }

    override var storageVersion: Int {
        return TabsStorageVersion
    }

    var tabsRecordLastUpload: Timestamp {
        set(value) {
            self.prefs.setLong(value, forKey: "lastTabsUpload")
        }

        get {
            return self.prefs.unsignedLongForKey("lastTabsUpload") ?? 0
        }
    }

    private func createOwnTabsRecord(tabs: [RemoteTab]) -> Record<TabsPayload> {
        let guid = self.scratchpad.clientGUID

        let jsonTabs: [JSON] = optFilter(tabs.map { $0.toJSON() })
        let tabsJSON = JSON([
            "id": guid,
            "clientName": self.scratchpad.clientName,
            "tabs": jsonTabs
        ])
        log.debug("Sending tabs JSON \(tabsJSON.toString(pretty: true))")
        let payload = TabsPayload(tabsJSON)
        return Record(id: guid, payload: payload, ttl: ThreeWeeksInSeconds)
    }

    private func uploadOurTabs(localTabs: RemoteClientsAndTabs, toServer tabsClient: Sync15CollectionClient<TabsPayload>) -> Success{
        // check to see if our tabs have changed or we're in a fresh start
        let lastUploadTime: Timestamp? = (self.tabsRecordLastUpload == 0) ? nil : self.tabsRecordLastUpload
        let expired = lastUploadTime < (NSDate.now() - (OneMinuteInMilliseconds))
        if !expired {
            return succeed()
        }

        return localTabs.getTabsForClientWithGUID(nil) >>== { tabs in
            if let lastUploadTime = lastUploadTime {
                // TODO: track this in memory so we don't have to hit the disk to figure out when our tabs have
                // changed and need to be uploaded.
                if tabs.every({ $0.lastUsed < lastUploadTime }) {
                    return succeed()
                }
            }

            let tabsRecord = self.createOwnTabsRecord(tabs)

            // We explicitly don't send If-Unmodified-Since, because we always
            // want our upload to succeed -- we own the record.
            return tabsClient.put(tabsRecord, ifUnmodifiedSince: nil) >>== { resp in
                if let ts = resp.metadata.lastModifiedMilliseconds {
                    // Protocol says this should always be present for success responses.
                    log.debug("Tabs record upload succeeded. New timestamp: \(ts).")
                    self.tabsRecordLastUpload = ts
                }
                return succeed()
            }
        }
    }

    public func synchronizeLocalTabs(localTabs: RemoteClientsAndTabs, withServer storageClient: Sync15StorageClient, info: InfoCollections) -> SyncResult {
        func onResponseReceived(response: StorageResponse<[Record<TabsPayload>]>) -> Success {

            func afterWipe() -> Success {
                log.info("Fetching tabs.")
                func doInsert(record: Record<TabsPayload>) -> Deferred<Result<(Int)>> {
                    let remotes = record.payload.remoteTabs
                    log.debug("\(remotes)")
                    log.info("Inserting \(remotes.count) tabs for client \(record.id).")
                    return localTabs.insertOrUpdateTabsForClientGUID(record.id, tabs: remotes)
                }

                let ourGUID = self.scratchpad.clientGUID

                let records = response.value
                let responseTimestamp = response.metadata.lastModifiedMilliseconds

                log.debug("Got \(records.count) tab records.")

                let allDone = all(records.filter({ $0.id != ourGUID }).map(doInsert))
                return allDone.bind { (results) -> Success in
                    if let failure = find(results, { $0.isFailure }) {
                        return deferResult(failure.failureValue!)
                    }

                    self.lastFetched = responseTimestamp!
                    return succeed()
                }
            }

            // If this is a fresh start, do a wipe.
            if self.lastFetched == 0 {
                log.info("Last fetch was 0. Wiping tabs.")
                return localTabs.wipeRemoteTabs()
                    >>== afterWipe
            }

            return afterWipe()
        }

        if let reason = self.reasonToNotSync(storageClient) {
            return deferResult(SyncStatus.NotStarted(reason))
        }

        let keys = self.scratchpad.keys?.value
        let encoder = RecordEncoder<TabsPayload>(decode: { TabsPayload($0) }, encode: { $0 })
        if let encrypter = keys?.encrypter(self.collection, encoder: encoder) {
            let tabsClient = storageClient.clientForCollection(self.collection, encrypter: encrypter)

            if !self.remoteHasChanges(info) {
                // upload local tabs if they've changed or we're in a fresh start.
                uploadOurTabs(localTabs, toServer: tabsClient)
                return deferResult(.Completed)
            }

            return tabsClient.getSince(self.lastFetched)
                >>== onResponseReceived
                >>> { self.uploadOurTabs(localTabs, toServer: tabsClient) }
                >>> { deferResult(.Completed) }
        }

        log.error("Couldn't make tabs factory.")
        return deferResult(FatalError(message: "Couldn't make tabs factory."))
    }
}

extension RemoteTab {
    public func toJSON() -> JSON? {
        let tabHistory = optFilter(history.map { $0.absoluteString })
        if !tabHistory.isEmpty {
            return JSON([
                "title": title,
                "icon": icon?.absoluteString ?? NSNull(),
                "urlHistory": tabHistory,
                "lastUsed": lastUsed.description,
                ])
        }
        return nil
    }
}
