import Storage
import Shared
import Alamofire
import XCGLogger

private let log = Logger.browserLogger
private let queue = dispatch_queue_create("FaviconFetcher", DISPATCH_QUEUE_CONCURRENT)

class FaviconFetcherErrorType: ErrorType {
    let description: String
    init(description: String) {
        self.description = description
    }
}

/* A helper class to find the favicon associated with a URL.
 * This will load the page and parse any icons it finds out of it.
 * If that fails, it will attempt to find a favicon.ico in the root host domain.
 */
public class FaviconFetcher : NSObject, NSXMLParserDelegate {
    public static var userAgent: String = ""
    static let ExpirationTime = NSTimeInterval(60*60*24*7) // Only check for icons once a week

    class func getForURL(url: NSURL, profile: Profile) -> Deferred<Result<[Favicon]>> {
        let f = FaviconFetcher()
        return f.loadFavicons(url, profile: profile)
    }

    private func loadFavicons(url: NSURL, profile: Profile, var oldIcons: [Favicon] = [Favicon]()) -> Deferred<Result<[Favicon]>> {
        if isIgnoredURL(url) {
            return deferResult(FaviconFetcherErrorType(description: "Not fetching ignored URL to find favicons."))
        }

        let deferred = Deferred<Result<[Favicon]>>()

        dispatch_async(queue) { _ in
            self.parseHTMLForFavicons(url).bind({ (result: Result<[Favicon]>) -> Deferred<[Result<Favicon>]> in
                var deferreds = [Deferred<Result<Favicon>>]()
                if let icons = result.successValue {
                    deferreds = map(icons) { self.getFavicon(url, icon: $0, profile: profile) }
                }
                return all(deferreds)
            }).bind({ (results: [Result<Favicon>]) -> Deferred<Result<[Favicon]>> in
                for result in results {
                    if let icon = result.successValue {
                        oldIcons.append(icon)
                    }
                }

                oldIcons.sort({ (a, b) -> Bool in
                    return a.width > b.width
                })

                return deferResult(oldIcons)
            }).upon({ (result: Result<[Favicon]>) in
                deferred.fill(result)
                return
            })
        }

        return deferred
    }

    lazy private var alamofire: Alamofire.Manager = {
        var defaultHeaders = Alamofire.Manager.sharedInstance.session.configuration.HTTPAdditionalHeaders ?? [:]
        defaultHeaders["User-Agent"] = userAgent

        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.timeoutIntervalForRequest = 5
        configuration.HTTPAdditionalHeaders = defaultHeaders

        return Alamofire.Manager(configuration: configuration)
    }()

    private func fetchDataForURL(url: NSURL) -> Deferred<Result<NSData>> {
        let deferred = Deferred<Result<NSData>>()
        alamofire.request(.GET, url).response { (request, response, data, error) in
            if error == nil {
                if let data = data as? NSData {
                    deferred.fill(Result(success: data))
                    return
                }
            }

            deferred.fill(Result(failure: FaviconFetcherErrorType(description: error?.description ?? "No content.")))
        }
        return deferred
    }

    // Loads and parses an html document and tries to find any known favicon-type tags for the page
    private func parseHTMLForFavicons(url: NSURL) -> Deferred<Result<[Favicon]>> {
        var err: NSError?

        return fetchDataForURL(url).bind({ result -> Deferred<Result<[Favicon]>> in
            var icons = [Favicon]()

            if let data = result.successValue where result.isSuccess,
               let element = RXMLElement(fromHTMLData: data) where element.isValid {
                var reloadUrl: NSURL? = nil
                element.iterate("head.meta") { meta in
                    if let refresh = meta.attribute("http-equiv") where refresh == "Refresh",
                        let content = meta.attribute("content"),
                        let index = content.rangeOfString("URL="),
                        let url = NSURL(string: content.substringFromIndex(advance(index.startIndex,4))) {
                            reloadUrl = url
                    }
                }

                if let url = reloadUrl {
                    return self.parseHTMLForFavicons(url)
                }

                element.iterate("head.link") { link in
                    if let rel = link.attribute("rel") where (rel == "shortcut icon" || rel == "icon" || rel == "apple-touch-icon"),
                        let href = link.attribute("href"),
                        let url = NSURL(string: href, relativeToURL: url) {
                            let icon = Favicon(url: url.absoluteString!, date: NSDate(), type: IconType.Icon)
                            icons.append(icon)
                    }
                }
            }

            return deferResult(icons)
        })
    }

    private func getFavicon(siteUrl: NSURL, icon: Favicon, profile: Profile) -> Deferred<Result<Favicon>> {
        let deferred = Deferred<Result<Favicon>>()
        let url = icon.url
        let manager = SDWebImageManager.sharedManager()
        let site = Site(url: siteUrl.absoluteString!, title: "")

        var fav = Favicon(url: url, type: icon.type)
        if let url = url.asURL {
            manager.downloadImageWithURL(url, options: SDWebImageOptions.LowPriority, progress: nil, completed: { (img, err, cacheType, success, url) -> Void in
                fav = Favicon(url: url.absoluteString!,
                    type: icon.type)

                if let img = img {
                    fav.width = Int(img.size.width)
                    fav.height = Int(img.size.height)
                    profile.favicons.addFavicon(fav, forSite: site)
                } else {
                    fav.width = 0
                    fav.height = 0
                }

                deferred.fill(Result(success: fav))
            })
        } else {
            return deferResult(FaviconFetcherErrorType(description: "Invalid URL \(url)"))
        }

        return deferred
    }
}

