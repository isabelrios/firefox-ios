/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

private let ReaderModeCacheSharedInstance = ReaderModeCache()

/// Really basic persistent cache to store readerized content. Has a simple hashed structure
/// to avoid storing many items in the same directory.
///
/// This currently lives in ~/Library/Caches so that the data can be pruned in case the OS needs
/// more space. Whether that is a good idea or not is not sure. We have a bug on file to investigate
/// and improve at a later time.

class ReaderModeCache {
    class var sharedInstance: ReaderModeCache {
        return ReaderModeCacheSharedInstance
    }

    func put(url: NSURL, _ readabilityResult: ReadabilityResult) throws {
        var error: NSError! = NSError(domain: "Migrator", code: 0, userInfo: nil)
        if let cacheDirectoryPath = cacheDirectoryForURL(url) {
            do {
                try NSFileManager.defaultManager().createDirectoryAtPath(cacheDirectoryPath as String, withIntermediateDirectories: true, attributes: nil)
                let contentFilePath = cacheDirectoryPath.stringByAppendingPathComponent("content.json")
                let string: NSString = readabilityResult.encode()
                # /* TODO: Finish migration: rewrite code to move the next statement out of enclosing do/catch */
                try string.writeToFile(contentFilePath, atomically: true, encoding: NSUTF8StringEncoding)
                return
            } catch let error1 as NSError {
                error = error1
            }
        }
        throw error
    }

    func get(url: NSURL) throws -> ReadabilityResult {
        var error: NSError! = NSError(domain: "Migrator", code: 0, userInfo: nil)
        if let cacheDirectoryPath = cacheDirectoryForURL(url) {
            let contentFilePath = cacheDirectoryPath.stringByAppendingPathComponent("content.json")
            if NSFileManager.defaultManager().fileExistsAtPath(contentFilePath) {
                do {
                    let string = try NSString(contentsOfFile: contentFilePath, encoding: NSUTF8StringEncoding)
                    if let value = ReadabilityResult(string: string as String) {
                        return value
                    }
                    # /* TODO: Finish migration: rewrite code to move the next statement out of enclosing do/catch */
                    throw error
                } catch let error1 as NSError {
                    error = error1
                }
            }
        }
        throw error
    }

    func delete(url: NSURL, error: NSErrorPointer) {
        if let cacheDirectoryPath = cacheDirectoryForURL(url) {
            if NSFileManager.defaultManager().fileExistsAtPath(cacheDirectoryPath) {
                do {
                    try NSFileManager.defaultManager().removeItemAtPath(cacheDirectoryPath)
                } catch let error1 as NSError {
                    error.memory = error1
                }
            }
        }
    }

    func contains(url: NSURL) throws {
        let error: NSError! = NSError(domain: "Migrator", code: 0, userInfo: nil)
        if let cacheDirectoryPath = cacheDirectoryForURL(url) {
            let contentFilePath = cacheDirectoryPath.stringByAppendingPathComponent("content.json")
            if NSFileManager.defaultManager().fileExistsAtPath(contentFilePath) {
                return
            }
            throw error
        }
        throw error
    }

    private func cacheDirectoryForURL(url: NSURL) -> String? {
        if let paths = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.CachesDirectory, NSSearchPathDomainMask.UserDomainMask, true) as? [String] {
            if paths.count > 0 {
                if let hashedPath = hashedPathForURL(url) {
                   return NSString.pathWithComponents([paths[0], "ReaderView", hashedPath]) as String
                }
            }
        }
        return nil
    }

    private func hashedPathForURL(url: NSURL) -> String? {
        if let hash = hashForURL(url) {
            return NSString.pathWithComponents([hash.substringWithRange(NSMakeRange(0, 2)), hash.substringWithRange(NSMakeRange(2, 2)), hash.substringFromIndex(4)]) as String
        }
        return nil
    }

    private func hashForURL(url: NSURL) -> NSString? {
        if let absoluteString = url.absoluteString {
            if let data = absoluteString.dataUsingEncoding(NSUTF8StringEncoding) {
                return data.sha1.hexEncodedString
            }
        }
        return nil
    }
}