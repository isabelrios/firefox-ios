// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared
import Storage

class TopSitesViewModel {

    struct UX {
        static let numberOfItemsPerRowForSizeClassIpad = UXSizeClasses(compact: 3, regular: 4, other: 2)
        static let cellEstimatedSize: CGSize = CGSize(width: 100, height: 120)
    }

    weak var delegate: HomepageDataModelDelegate?
    var isZeroSearch: Bool
    var tilePressedHandler: ((Site, Bool) -> Void)?
    var tileLongPressedHandler: ((Site, UIView?) -> Void)?

    private let profile: Profile
    private var sentImpressionTelemetry = [String: Bool]()
    private var topSites: [TopSite] = []
    private let dimensionManager: TopSitesDimension

    private let topSitesDataAdaptor: TopSitesDataAdaptor
    private let topSiteHistoryManager: TopSiteHistoryManager
    private let googleTopSiteManager: GoogleTopSiteManager

    init(profile: Profile, isZeroSearch: Bool = false) {
        self.profile = profile
        self.isZeroSearch = isZeroSearch
        self.dimensionManager = TopSitesDimensionImplementation()

        self.topSiteHistoryManager = TopSiteHistoryManager(profile: profile)
        self.googleTopSiteManager = GoogleTopSiteManager(prefs: profile.prefs)
        let adaptor = TopSitesDataAdaptorImplementation(profile: profile,
                                                        topSiteHistoryManager: topSiteHistoryManager,
                                                        googleTopSiteManager: googleTopSiteManager)
        topSitesDataAdaptor = adaptor
        adaptor.delegate = self
    }

    func tilePressed(site: TopSite, position: Int) {
        topSitePressTracking(homeTopSite: site, position: position)
        tilePressedHandler?(site.site, site.isGoogleURL)
    }

    // MARK: - Telemetry

    func sendImpressionTelemetry(_ homeTopSite: TopSite, position: Int) {
        guard !hasSentImpressionForTile(homeTopSite) else { return }
        homeTopSite.impressionTracking(position: position)
    }

    private func topSitePressTracking(homeTopSite: TopSite, position: Int) {
        // Top site extra
        let type = homeTopSite.getTelemetrySiteType()
        let topSiteExtra = [TelemetryWrapper.EventExtraKey.topSitePosition.rawValue: "\(position)",
                            TelemetryWrapper.EventExtraKey.topSiteTileType.rawValue: type]

        // Origin extra
        let originExtra = TelemetryWrapper.getOriginExtras(isZeroSearch: isZeroSearch)
        let extras = originExtra.merge(with: topSiteExtra)

        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .topSiteTile,
                                     value: nil,
                                     extras: extras)

        // Sponsored tile specific telemetry
        if let tile = homeTopSite.site as? SponsoredTile {
            SponsoredTileTelemetry.sendClickTelemetry(tile: tile, position: position)
        }
    }

    private func hasSentImpressionForTile(_ homeTopSite: TopSite) -> Bool {
        guard sentImpressionTelemetry[homeTopSite.site.url] != nil else {
            sentImpressionTelemetry[homeTopSite.site.url] = true
            return false
        }
        return true
    }

    // MARK: - Context actions

    func hideURLFromTopSites(_ site: Site) {
        guard let host = site.tileURL.normalizedHost else { return }
        topSiteHistoryManager.removeDefaultTopSitesTile(site: site)

        profile.history.removeHostFromTopSites(host).uponQueue(.main) { [weak self] result in
            guard result.isSuccess, let self = self else { return }
            self.refreshIfNeeded(refresh: true)
        }
    }

    func pinTopSite(_ site: Site) {
        profile.history.addPinnedTopSite(site).uponQueue(.main) { result in
            guard result.isSuccess else { return }
            self.refreshIfNeeded(refresh: true)
        }
    }

    func removePinTopSite(_ site: Site) {
        googleTopSiteManager.removeGoogleTopSite(site: site)
        topSiteHistoryManager.removeTopSite(site: site)
    }

    func refreshIfNeeded(refresh forced: Bool) {
        topSiteHistoryManager.refreshIfNeeded(forceRefresh: forced)
    }
}

// MARK: HomeViewModelProtocol
extension TopSitesViewModel: HomepageViewModelProtocol, FeatureFlaggable {

    var sectionType: HomepageSectionType {
        return .topSites
    }

    var headerViewModel: LabelButtonHeaderViewModel {
        // Only show a header if the firefox browser logo isn't showing
        let shouldShow = !featureFlags.isFeatureEnabled(.wallpapers, checking: .buildOnly)
        return LabelButtonHeaderViewModel(title: shouldShow ? HomepageSectionType.topSites.title: nil,
                                          titleA11yIdentifier: AccessibilityIdentifiers.FirefoxHomepage.SectionTitles.topSites,
                                          isButtonHidden: true)
    }

    var isEnabled: Bool {
        return featureFlags.isFeatureEnabled(.topSites, checking: .buildAndUser)
    }

    func numberOfItemsInSection(for traitCollection: UITraitCollection) -> Int {
        refreshData(for: traitCollection)

        let interface = TopSitesUIInterface(trait: traitCollection)
        let sectionDimension = dimensionManager.getSectionDimension(for: topSites,
                                                                    numberOfRows: topSitesDataAdaptor.numberOfRows,
                                                                    interface: interface)
        let items = sectionDimension.numberOfRows * sectionDimension.numberOfTilesPerRow
        return items
    }

    func section(for traitCollection: UITraitCollection) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(UX.cellEstimatedSize.height)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(UX.cellEstimatedSize.height)
        )

        let interface = TopSitesUIInterface(trait: traitCollection)
        let sectionDimension = dimensionManager.getSectionDimension(for: topSites,
                                                                    numberOfRows: topSitesDataAdaptor.numberOfRows,
                                                                    interface: interface)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: sectionDimension.numberOfTilesPerRow)
        let section = NSCollectionLayoutSection(group: group)

        let leadingInset = HomepageViewModel.UX.topSiteLeadingInset(traitCollection: traitCollection)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0,
                                                        leading: leadingInset,
                                                        bottom: HomepageViewModel.UX.spacingBetweenSections - TopSiteItemCell.UX.bottomSpace,
                                                        trailing: 0)

        return section
    }

    var hasData: Bool {
        return !topSites.isEmpty
    }

    func updateData(completion: @escaping () -> Void) {
        topSites = topSitesDataAdaptor.getTopSitesData()
        completion()
    }

    func refreshData(for traitCollection: UITraitCollection) {
        let interface = TopSitesUIInterface(trait: traitCollection)
        let sectionDimension = dimensionManager.getSectionDimension(for: topSites,
                                                                    numberOfRows: topSitesDataAdaptor.numberOfRows,
                                                                    interface: interface)
        topSitesDataAdaptor.recalculateTopSiteData(for: sectionDimension.numberOfTilesPerRow)
        topSites = topSitesDataAdaptor.getTopSitesData()
    }
}

// MARK: - FxHomeTopSitesManagerDelegate
extension TopSitesViewModel: TopSitesManagerDelegate {
    func didLoadNewData() {
        topSites = topSitesDataAdaptor.getTopSitesData()
        delegate?.reloadData()
    }
}

// MARK: - FxHomeSectionHandler
extension TopSitesViewModel: HomepageSectionHandler {

    func configure(_ collectionView: UICollectionView,
                   at indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(cellType: TopSiteItemCell.self, for: indexPath),
           let contentItem = topSites[safe: indexPath.row] {
            cell.configure(contentItem, position: indexPath.row)
            sendImpressionTelemetry(contentItem, position: indexPath.row)
            return cell

        } else if let cell = collectionView.dequeueReusableCell(cellType: EmptyTopSiteCell.self, for: indexPath) {
            return cell
        }

        return UICollectionViewCell()
    }

    func configure(_ cell: UICollectionViewCell,
                   at indexPath: IndexPath) -> UICollectionViewCell {
        // Setup is done through configure(collectionView:indexPath:), shouldn't be called
        return UICollectionViewCell()
    }

    func didSelectItem(at indexPath: IndexPath,
                       homePanelDelegate: HomePanelDelegate?,
                       libraryPanelDelegate: LibraryPanelDelegate?) {

        guard let site = topSites[safe: indexPath.row]  else { return }

        tilePressed(site: site, position: indexPath.row)
    }

    func handleLongPress(with collectionView: UICollectionView, indexPath: IndexPath) {
        guard let tileLongPressedHandler = tileLongPressedHandler,
              let site = topSites[safe: indexPath.row]?.site
        else { return }

        let sourceView = collectionView.cellForItem(at: indexPath)
        tileLongPressedHandler(site, sourceView)
    }
}
