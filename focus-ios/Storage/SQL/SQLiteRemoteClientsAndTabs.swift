/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import XCGLogger

private let log = XCGLogger.defaultInstance()

public class DatabaseError: ErrorType {
    let err: NSError?

    public var description: String {
        return err?.localizedDescription ?? "Unknown database error."
    }

    init(err: NSError?) {
        self.err = err
    }
}

public class SQLiteRemoteClientsAndTabs: RemoteClientsAndTabs {
    let files: FileAccessor
    let db: BrowserDB
    let clients = RemoteClientsTable<RemoteClient>()
    let tabs = RemoteTabsTable<RemoteTab>()

    public init(files: FileAccessor) {
        self.files = files
        self.db = BrowserDB(files: files)!
        db.createOrUpdate(clients)
        db.createOrUpdate(tabs)
    }

    public func clear() -> Deferred<Result<()>> {
        let deferred = Deferred<Result<()>>(defaultQueue: dispatch_get_main_queue())

        var err: NSError?
        db.transaction(&err) { connection, _ in
            self.tabs.delete(connection, item: nil, err: &err)
            self.clients.delete(connection, item: nil, err: &err)
            if let err = err {
                let databaseError = DatabaseError(err: err)
                log.debug("Clear failed: \(databaseError)")
                deferred.fill(Result(failure: databaseError))
            } else {
                deferred.fill(Result(success: ()))
            }
            return true
        }

        return deferred
    }

    public func insertOrUpdateTabsForClient(client: String, tabs: [RemoteTab]) -> Deferred<Result<Int>> {
        let deferred = Deferred<Result<Int>>(defaultQueue: dispatch_get_main_queue())

        let deleteQuery = "DELETE FROM \(self.tabs.name) WHERE client_guid = ?"
        let deleteArgs: [AnyObject?] = [client]

        var err: NSError?

        db.transaction(&err) { connection, _ in
            // Delete any existing tabs.
            if let error = connection.executeChange(deleteQuery, withArgs: deleteArgs) {
                deferred.fill(Result(failure: DatabaseError(err: err)))
                return false
            }

            // Insert replacement tabs.
            var inserted = 0
            var err: NSError?
            for tab in tabs {
                // We trust that each tab's clientGUID matches the supplied client!
                // Really tabs shouldn't have a GUID at all. Future cleanup!
                inserted += self.tabs.insert(connection, item: tab, err: &err)
                if let err = err {
                    deferred.fill(Result(failure: DatabaseError(err: err)))
                    return false
                }
            }

            deferred.fill(Result(success: inserted))
            return true
        }

        return deferred
    }

    public func insertOrUpdateClient(client: RemoteClient) -> Deferred<Result<()>> {
        let deferred = Deferred<Result<()>>(defaultQueue: dispatch_get_main_queue())

        var err: NSError?
        // TODO: insert multiple clients in a single transaction, and a single-query.
        // ORM systems are foolish.
        db.transaction(&err) { connection, _ in
            // Update or insert client record.
            let updated = self.clients.update(connection, item: client, err: &err)
            log.info("Updated clients: \(updated)")
            if updated == 0 {
                let inserted = self.clients.insert(connection, item: client, err: &err)
                log.info("Inserted clients: \(inserted)")
            }

            if let err = err {
                let databaseError = DatabaseError(err: err)
                log.debug("insertOrUpdateClient failed: \(databaseError)")
                deferred.fill(Result(failure: databaseError))
                return false
            }

            deferred.fill(Result(success: ()))
            return true
        }

        return deferred
    }

    public func getClients() -> Deferred<Result<[RemoteClient]>> {
        var err: NSError?

        let clientCursor = db.query(&err) { connection, _ in
            return self.clients.query(connection, options: nil)
        }

        if let err = err {
            clientCursor.close()
            return Deferred(value: Result(failure: DatabaseError(err: err)))
        }

        let clients = clientCursor.mapAsType(RemoteClient.self, f: { $0 })
        clientCursor.close()

        return Deferred(value: Result(success: clients))
    }

    public func getClientsAndTabs() -> Deferred<Result<[ClientAndTabs]>> {
        var err: NSError?

        // Now find the clients.
        let clientCursor = db.query(&err) { connection, _ in
            return self.clients.query(connection, options: nil)
        }

        if let err = err {
            clientCursor.close()
            return Deferred(value: Result(failure: DatabaseError(err: err)))
        }

        let clients = clientCursor.mapAsType(RemoteClient.self, f: { $0 })
        clientCursor.close()

        log.info("Found \(clients.count) clients in the DB.")

        let tabCursor = db.query(&err) { connection, _ in
            return self.tabs.query(connection, options: nil)
        }

        log.info("Found \(tabCursor.count) raw tabs in the DB.")

        if let err = err {
            tabCursor.close()
            return Deferred(value: Result(failure: DatabaseError(err: err)))
        }

        let deferred = Deferred<Result<[ClientAndTabs]>>(defaultQueue: dispatch_get_main_queue())

        // Aggregate clientGUID -> RemoteTab.
        var acc = [String: [RemoteTab]]()
        for tab in tabCursor {
            if let tab = tab as? RemoteTab {
                if acc[tab.clientGUID] == nil {
                    acc[tab.clientGUID] = [tab]
                } else {
                    acc[tab.clientGUID]!.append(tab)
                }
            } else {
                log.error("Couldn't cast tab \(tab) to RemoteTab.")
            }
        }

        tabCursor.close()
        log.info("Accumulated tabs with client GUIDs \(acc.keys).")

        // Most recent first.
        let sort: (RemoteTab, RemoteTab) -> Bool = { $0.lastUsed > $1.lastUsed }
        let f: (RemoteClient) -> ClientAndTabs = { client in
            let guid: String = client.guid
            let tabs = acc[guid]   // ?.sorted(sort)   // The sort should be unnecessary: the DB does that.
            return ClientAndTabs(client: client, tabs: tabs ?? [])
        }

        // Why is this whole function synchronous?
        deferred.fill(Result(success: clients.map(f)))
        return deferred
    }

    private let debug_enabled = true
    private func debug(msg: String) {
        if debug_enabled {
            log.info(msg)
        }
    }
}
