/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import XCGLogger
import Storage

private let log = XCGLogger.defaultInstance()

private let ThumbnailIdentifier = "Thumbnail"

class Tile: Site {
    let backgroundColor: UIColor
    let trackingId: Int
    let wordmark: Favicon

    init(json: JSON) {
        let colorString = json["bgcolor"].asString!
        var colorInt: UInt32 = 0
        NSScanner(string: colorString).scanHexInt(&colorInt)
        self.backgroundColor = UIColor(rgb: (Int) (colorInt ?? 0xaaaaaa))
        self.trackingId = json["trackingid"].asInt ?? 0
        self.wordmark = Favicon(url: json["imageurl"].asString!, date: NSDate(), type: .Icon)

        super.init(url: json["url"].asString!, title: json["title"].asString!)

        self.icon = Favicon(url: json["faviconUrl"].asString!, date: NSDate(), type: .Icon)
    }
}

class SuggestedSitesData<T: Tile>: Cursor<T> {
    var tiles = [T]()

    init() {
        // TODO: Make this list localized. That should be as simple as making sure its in the lproj directory.
        var err: NSError? = nil
        let path = NSBundle.mainBundle().pathForResource("suggestedsites", ofType: "json")
        let data = NSString(contentsOfFile: path!, encoding: NSUTF8StringEncoding, error: &err)
        let json = JSON.parse(data as! String)

        for i in 0..<json.length {
            let t = T(json: json[i])
            tiles.append(t)
        }
    }

    override var count: Int {
        return tiles.count
    }

    override subscript(index: Int) -> T? {
        get {
            return tiles[index]
        }
    }
}

extension UIView {
    public class func viewOrientationForSize(size: CGSize) -> UIInterfaceOrientation {
        return size.width > size.height ? UIInterfaceOrientation.LandscapeRight : UIInterfaceOrientation.Portrait
    }
}

class TopSitesPanel: UIViewController {
    weak var homePanelDelegate: HomePanelDelegate?

    private var collection: TopSitesCollectionView? = nil
    private lazy var dataSource: TopSitesDataSource = {
        return TopSitesDataSource(profile: self.profile, data: Cursor(status: .Failure, msg: "Nothing loaded yet"))
    }()
    private lazy var layout: TopSitesLayout = { return TopSitesLayout() }()

    var editingThumbnails: Bool = false {
        didSet {
            if editingThumbnails != oldValue {
                dataSource.editingThumbnails = editingThumbnails

                if editingThumbnails {
                    homePanelDelegate?.homePanelWillEnterEditingMode?(self)
                }

                updateRemoveButtonStates()
            }
        }
    }

    let profile: Profile

    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)
        self.refreshHistory(self.layout.thumbnailCount)
        self.layout.setupForOrientation(UIView.viewOrientationForSize(size))
    }

    override func supportedInterfaceOrientations() -> Int {
        return Int(UIInterfaceOrientationMask.AllButUpsideDown.rawValue)
    }

    init(profile: Profile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "notificationReceived:", name: NotificationFirefoxAccountChanged, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "notificationReceived:", name: NotificationPrivateDataCleared, object: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        var collection = TopSitesCollectionView(frame: self.view.frame, collectionViewLayout: layout)
        collection.backgroundColor = UIConstants.PanelBackgroundColor
        collection.delegate = self
        collection.dataSource = dataSource
        collection.registerClass(ThumbnailCell.self, forCellWithReuseIdentifier: ThumbnailIdentifier)
        collection.keyboardDismissMode = .OnDrag
        view.addSubview(collection)
        collection.snp_makeConstraints { make in
            make.edges.equalTo(self.view)
        }
        self.collection = collection
        self.refreshHistory(layout.thumbnailCount)
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationFirefoxAccountChanged, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationPrivateDataCleared, object: nil)
    }
    
    func notificationReceived(notification: NSNotification) {
        switch notification.name {
        case NotificationFirefoxAccountChanged, NotificationPrivateDataCleared:
            refreshHistory(self.layout.thumbnailCount)
            break
        default:
            // no need to do anything at all
            log.warning("Received unexpected notification \(notification.name)")
            break
        }
    }

    //MARK: Private Helpers
    private func updateDataSourceWithSites(result: Result<Cursor<Site>>) {
        if let data = result.successValue {
            self.dataSource.data = data
            self.dataSource.profile = self.profile

            // redraw now we've udpated our sources
            self.collection?.collectionViewLayout.invalidateLayout()
            self.collection?.setNeedsLayout()
        }
    }

    private func updateRemoveButtonStates() {
        for i in 0..<layout.thumbnailCount {
            if let cell = collection?.cellForItemAtIndexPath(NSIndexPath(forItem: i, inSection: 0)) as? ThumbnailCell {
                //TODO: Only toggle the remove button for non-suggested tiles for now
                if i < dataSource.data.count {
                    cell.toggleRemoveButton(editingThumbnails)
                } else {
                    cell.toggleRemoveButton(false)
                }
            }
        }
    }

    private func deleteHistoryTileForURL(site: Site, atIndexPath indexPath: NSIndexPath) {
        profile.history.removeSiteFromTopSites(site) >>== {
            self.profile.history.getSitesByFrecencyWithLimit(self.layout.thumbnailCount).uponQueue(dispatch_get_main_queue(), block: { result in
                self.updateDataSourceWithSites(result)
                self.deleteOrUpdateSites(result, indexPath: indexPath)
            })
        }
    }

    private func refreshHistory(frequencyLimit: Int) {
        // We double the requested limit in order to generate some leeway for "grouping by domain". Hopefully
        // that returns enough entries that we can group but still have frequencyLimit results.
        self.profile.history.getSitesByFrecencyWithLimit(frequencyLimit).uponQueue(dispatch_get_main_queue(), block: { result in
            self.updateDataSourceWithSites(result)
            self.collection?.reloadData()
        })
    }

    private func deleteOrUpdateSites(result: Result<Cursor<Site>>, indexPath: NSIndexPath) {
        if let data = result.successValue {
            let numOfThumbnails = self.layout.thumbnailCount
            collection?.performBatchUpdates({
                // If we have enough data to fill the tiles after the deletion, then delete and insert the next one from data
                if (data.count + self.dataSource.suggestedSites.count >= numOfThumbnails) {
                    self.collection?.deleteItemsAtIndexPaths([indexPath])
                    self.collection?.insertItemsAtIndexPaths([NSIndexPath(forItem: numOfThumbnails - 1, inSection: 0)])
                }

                // If we don't have enough to fill the thumbnail tile area even with suggested tiles, just delete
                else if (data.count + self.dataSource.suggestedSites.count) < numOfThumbnails {
                    self.collection?.deleteItemsAtIndexPaths([indexPath])
                }
            }, completion: { _ in
                self.updateRemoveButtonStates()
            })
        }
    }
}

extension TopSitesPanel: HomePanel {
    func endEditing() {
        editingThumbnails = false
    }
}

extension TopSitesPanel: UICollectionViewDelegate {
    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        if editingThumbnails {
            return
        }

        if let site = dataSource[indexPath.item] {
            // We're gonna call Top Sites bookmarks for now.
            let visitType = VisitType.Bookmark
            homePanelDelegate?.homePanel(self, didSelectURL: NSURL(string: site.url)!, visitType: visitType)
        }
    }

    func collectionView(collectionView: UICollectionView, willDisplayCell cell: UICollectionViewCell, forItemAtIndexPath indexPath: NSIndexPath) {
        if let thumbnailCell = cell as? ThumbnailCell {
            thumbnailCell.delegate = self

            if editingThumbnails && indexPath.item < dataSource.data.count && thumbnailCell.removeButton.hidden {
                thumbnailCell.removeButton.hidden = false
            }
        }
    }
}

extension TopSitesPanel: ThumbnailCellDelegate {
    func didRemoveThumbnail(thumbnailCell: ThumbnailCell) {
        if let indexPath = collection?.indexPathForCell(thumbnailCell) {
            if let site = dataSource[indexPath.item] {
                self.deleteHistoryTileForURL(site, atIndexPath: indexPath)
            }
        }
        
    }

    func didLongPressThumbnail(thumbnailCell: ThumbnailCell) {
        editingThumbnails = true
    }
}

private class TopSitesCollectionView: UICollectionView {
    private override func touchesBegan(touches: Set<NSObject>, withEvent event: UIEvent) {
        // Hide the keyboard if this view is touched.
        window?.rootViewController?.view.endEditing(true)
        super.touchesBegan(touches, withEvent: event)
    }
}

private class TopSitesLayout: UICollectionViewLayout {
    private var thumbnailRows: Int {
        return max(2, Int((self.collectionView?.frame.height ?? self.thumbnailHeight) / self.thumbnailHeight))
    }

    private var thumbnailCols = 2
    private var thumbnailCount: Int {
        return thumbnailRows * thumbnailCols
    }
    private var width: CGFloat { return self.collectionView?.frame.width ?? 0 }

    // The width and height of the thumbnail here are the width and height of the tile itself, not the image inside the tile.
    private var thumbnailWidth: CGFloat {
        let insets = ThumbnailCellUX.Insets
        return (width - insets.left - insets.right) / CGFloat(thumbnailCols) }
    // The tile's height is determined the aspect ratio of the thumbnails width. We also take into account
    // some padding between the title and the image.
    private var thumbnailHeight: CGFloat { return thumbnailWidth / CGFloat(ThumbnailCellUX.ImageAspectRatio) }

    // Used to calculate the height of the list.
    private var count: Int {
        if let dataSource = self.collectionView?.dataSource as? TopSitesDataSource {
            return dataSource.collectionView(self.collectionView!, numberOfItemsInSection: 0)
        }
        return 0
    }

    private var topSectionHeight: CGFloat {
        let maxRows = ceil(Float(count) / Float(thumbnailCols))
        let rows = min(Int(maxRows), thumbnailRows)
        let insets = ThumbnailCellUX.Insets
        return thumbnailHeight * CGFloat(rows) + insets.top + insets.bottom
    }

    override init() {
        super.init()
        setupForOrientation(UIApplication.sharedApplication().statusBarOrientation)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupForOrientation(orientation: UIInterfaceOrientation) {
        if orientation.isLandscape {
            thumbnailCols = 5
        } else if UIScreen.mainScreen().traitCollection.horizontalSizeClass == .Compact {
            thumbnailCols = 3
        } else {
            thumbnailCols = 4
        }
    }

    private func getIndexAtPosition(#y: CGFloat) -> Int {
        if y < topSectionHeight {
            let row = Int(y / thumbnailHeight)
            return min(count - 1, max(0, row * thumbnailCols))
        }
        return min(count - 1, max(0, Int((y - topSectionHeight) / UIConstants.DefaultRowHeight + CGFloat(thumbnailCount))))
    }

    override func collectionViewContentSize() -> CGSize {
        if count <= thumbnailCount {
            let row = floor(Double(count / thumbnailCols))
            return CGSize(width: width, height: topSectionHeight)
        }

        let bottomSectionHeight = CGFloat(count - thumbnailCount) * UIConstants.DefaultRowHeight
        return CGSize(width: width, height: topSectionHeight + bottomSectionHeight)
    }

    override func layoutAttributesForElementsInRect(rect: CGRect) -> [AnyObject]? {
        let start = getIndexAtPosition(y: rect.origin.y)
        let end = getIndexAtPosition(y: rect.origin.y + rect.height)

        var attrs = [UICollectionViewLayoutAttributes]()
        if start == -1 || end == -1 {
            return attrs
        }

        for i in start...end {
            let indexPath = NSIndexPath(forItem: i, inSection: 0)
            let attr = layoutAttributesForItemAtIndexPath(indexPath)
            attrs.append(attr)
        }
        return attrs
    }

    override func layoutAttributesForItemAtIndexPath(indexPath: NSIndexPath) -> UICollectionViewLayoutAttributes! {
        let attr = UICollectionViewLayoutAttributes(forCellWithIndexPath: indexPath)

        // Set the top thumbnail frames.
        let row = floor(Double(indexPath.item / thumbnailCols))
        let col = indexPath.item % thumbnailCols
        let insets = ThumbnailCellUX.Insets
        let x = insets.left + thumbnailWidth * CGFloat(col)
        let y = insets.top + CGFloat(row) * thumbnailHeight
        attr.frame = CGRectMake(ceil(x), ceil(y), thumbnailWidth, thumbnailHeight)

        return attr
    }
}

private class TopSitesDataSource: NSObject, UICollectionViewDataSource {
    var data: Cursor<Site>
    var profile: Profile
    var editingThumbnails: Bool = false

    lazy var suggestedSites: SuggestedSitesData<Tile> = {
        return SuggestedSitesData<Tile>()
    }()

    init(profile: Profile, data: Cursor<Site>) {
        self.data = data
        self.profile = profile
    }

    @objc func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if data.status != .Success {
            return 0
        }

        // If there aren't enough data items to fill the grid, look for items in suggested sites.
        if let layout = collectionView.collectionViewLayout as? TopSitesLayout {
            return min(data.count + suggestedSites.count, layout.thumbnailCount)
        }

        return 0
    }

    private func setDefaultThumbnailBackground(cell: ThumbnailCell) {
        cell.imageView.image = UIImage(named: "defaultTopSiteIcon")!
        cell.imageView.contentMode = UIViewContentMode.Center
    }

    private func getFavicon(cell: ThumbnailCell, site: Site) {
        // TODO: This won't work well with recycled views. Thankfully, TopSites doesn't really recycle much.'
        cell.imageView.image = nil
        cell.backgroundImage.image = nil

        if let url = site.url.asURL {
            FaviconFetcher.getForURL(url, profile: profile) >>== { icons in
                if (icons.count > 0) {
                    cell.imageView.sd_setImageWithURL(icons[0].url.asURL!) { (img, err, type, url) -> Void in
                        if let img = img {
                            cell.backgroundImage.image = img
                            cell.image = img
                        } else {
                            let icon = Favicon(url: "", date: NSDate(), type: IconType.NoneFound)
                            self.profile.favicons.addFavicon(icon, forSite: site)
                            self.setDefaultThumbnailBackground(cell)
                        }
                    }
                }
            }
        }
    }

    private func createTileForSite(cell: ThumbnailCell, site: Site) -> ThumbnailCell {
        cell.textLabel.text = site.title.isEmpty ? site.url : site.title
        cell.imageWrapper.backgroundColor = UIColor.clearColor()

        if let icon = site.icon {
            // We've looked before recently and didn't find a favicon
            switch icon.type {
            case .NoneFound:
                let t = NSDate().timeIntervalSinceDate(icon.date)
                if t < FaviconFetcher.ExpirationTime {
                    self.setDefaultThumbnailBackground(cell)
                }
            default:
                cell.imageView.sd_setImageWithURL(icon.url.asURL, completed: { (img, err, type, url) -> Void in
                    if let img = img {
                        cell.backgroundImage.image = img
                        cell.image = img
                    } else {
                        self.getFavicon(cell, site: site)
                    }
                })
            }
        } else {
            getFavicon(cell, site: site)
        }

        cell.isAccessibilityElement = true
        cell.accessibilityLabel = cell.textLabel.text
        cell.removeButton.hidden = !editingThumbnails
        return cell
    }

    private func createTileForSuggestedSite(cell: ThumbnailCell, tile: Tile) -> ThumbnailCell {
        cell.textLabel.text = tile.title.isEmpty ? tile.url : tile.title
        cell.imageWrapper.backgroundColor = tile.backgroundColor
        cell.backgroundImage.image = nil

        if let icon = tile.wordmark.url.asURL,
           let host = icon.host {
            if icon.scheme == "asset" {
                cell.imageView.image = UIImage(named: host)
            } else {
                cell.imageView.sd_setImageWithURL(icon, completed: { img, err, type, key in
                    if img == nil {
                        self.setDefaultThumbnailBackground(cell)
                    }
                })
            }
        } else {
            self.setDefaultThumbnailBackground(cell)
        }

        cell.imageView.contentMode = UIViewContentMode.ScaleAspectFit
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = cell.textLabel.text

        return cell
    }

    subscript(index: Int) -> Site? {
        if data.status != .Success {
            return nil
        }

        if index >= data.count {
            return suggestedSites[index - data.count]
        }
        return data[index] as Site?
    }

    @objc func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        // Cells for the top site thumbnails.
        let site = self[indexPath.item]!
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(ThumbnailIdentifier, forIndexPath: indexPath) as! ThumbnailCell

        if indexPath.item >= data.count {
            return createTileForSuggestedSite(cell, tile: site as! Tile)
        }
        return createTileForSite(cell, site: site)
    }
}
