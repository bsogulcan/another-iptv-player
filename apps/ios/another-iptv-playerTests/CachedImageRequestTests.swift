import Foundation
import Nuke
import SwiftUI
import Testing
import UIKit
@testable import another_iptv_player

/// Locks for the one request builder behind `CachedImage` and `ListImagePrefetch`. A
/// prefetch only warms a cell when both sides produce the same cache keys; if they drift
/// apart every image is downloaded once and decoded twice, and nothing on screen shows it.
@Suite("CachedImage requests")
struct CachedImageRequestTests {
    private let url = URL(string: "https://img.example.com/posters/1.jpg")!
    private let profiles: [ImageLoadProfile] = [.standard, .shelf, .grid, .high]
    private let modes: [SwiftUI.ContentMode] = [.fit, .fill]

    /// Memory key, disk key and everything the prefetcher matches a request by.
    private func sameKeys(_ lhs: ImageRequest, _ rhs: ImageRequest) -> Bool {
        let cache = ImagePipeline.shared.cache
        return cache.makeImageCacheKey(for: lhs) == cache.makeImageCacheKey(for: rhs)
            && cache.makeDataCacheKey(for: lhs) == cache.makeDataCacheKey(for: rhs)
            && lhs.imageID == rhs.imageID
            && lhs.thumbnail == rhs.thumbnail
            && lhs.options == rhs.options
            && lhs.processors.isEmpty && rhs.processors.isEmpty
    }

    // MARK: - Prefetch and render

    @Test
    func prefetchAndRenderShareTheirKeysForEveryProfile() throws {
        for profile in profiles {
            for mode in modes {
                let view = CachedImage(
                    url: url, width: 100, height: 150, contentMode: mode, loadProfile: profile
                )
                let prefetch = try #require(
                    ListImagePrefetch.requests(
                        urls: [url], width: 100, height: 150, contentMode: mode, loadProfile: profile
                    ).first
                )
                #expect(sameKeys(view.makeRequest(url: url), prefetch), "\(profile) \(mode)")
            }
        }
    }

    @Test
    func prefetchAndRenderShareTheirKeysWithADecodeOverride() throws {
        for profile in profiles {
            for mode in modes {
                // A 32 pt cell that decodes at the 90 pt bucket; the prefetch call passes
                // the bucket as its size.
                let view = CachedImage(
                    url: url, width: 32, height: 32, contentMode: mode, loadProfile: profile,
                    decodeWidth: 90, decodeHeight: 90
                )
                let prefetch = try #require(
                    ListImagePrefetch.requests(
                        urls: [url], width: 90, height: 90, contentMode: mode, loadProfile: profile
                    ).first
                )
                #expect(sameKeys(view.makeRequest(url: url), prefetch), "\(profile) \(mode)")
            }
        }
    }

    @Test
    func theLayoutSizeDoesNotMatterOnceTheDecodeSizeIsGiven() {
        for profile in profiles {
            let small = CachedImage.request(
                url: url, width: 32, height: 32, contentMode: .fit, loadProfile: profile,
                decodeWidth: 90, decodeHeight: 90
            )
            let large = CachedImage.request(
                url: url, width: 56, height: 44, contentMode: .fit, loadProfile: profile,
                decodeWidth: 90, decodeHeight: 90
            )
            #expect(sameKeys(small, large), "\(profile)")
        }
    }

    @Test
    func theDecodeSizeDefaultsToTheLayoutSizePerDimension() {
        let plain = CachedImage.request(
            url: url, width: 100, height: 150, contentMode: .fill, loadProfile: .grid
        )
        let explicitNil = CachedImage.request(
            url: url, width: 100, height: 150, contentMode: .fill, loadProfile: .grid,
            decodeWidth: nil, decodeHeight: nil
        )
        let widthOnly = CachedImage.request(
            url: url, width: 40, height: 150, contentMode: .fill, loadProfile: .grid,
            decodeWidth: 100
        )
        let heightOnly = CachedImage.request(
            url: url, width: 100, height: 60, contentMode: .fill, loadProfile: .grid,
            decodeHeight: 150
        )
        #expect(sameKeys(plain, explicitNil))
        #expect(sameKeys(plain, widthOnly))
        #expect(sameKeys(plain, heightOnly))
    }

    @Test
    func sizeAndContentModeSeparateCacheEntries() {
        let cache = ImagePipeline.shared.cache
        let poster = CachedImage.request(
            url: url, width: 100, height: 150, contentMode: .fill, loadProfile: .grid
        )
        let logo = CachedImage.request(
            url: url, width: 90, height: 90, contentMode: .fill, loadProfile: .grid
        )
        let fitted = CachedImage.request(
            url: url, width: 100, height: 150, contentMode: .fit, loadProfile: .grid
        )
        #expect(cache.makeImageCacheKey(for: poster) != cache.makeImageCacheKey(for: logo))
        #expect(cache.makeImageCacheKey(for: poster) != cache.makeImageCacheKey(for: fitted))
        #expect(cache.makeDataCacheKey(for: poster) != cache.makeDataCacheKey(for: logo))
        #expect(cache.makeDataCacheKey(for: poster) != cache.makeDataCacheKey(for: fitted))
    }

    // MARK: - Shape of the request

    @Test
    func requestsDownsampleWhileDecoding() {
        for profile in profiles {
            let scale = CachedImage.decodeScale(for: profile)
            let request = CachedImage.request(
                url: url, width: 100, height: 150, contentMode: .fill, loadProfile: profile
            )
            let expected = ImageRequest.ThumbnailOptions(
                size: CGSize(width: (100 * scale).rounded(.up), height: (150 * scale).rounded(.up)),
                unit: .pixels,
                contentMode: .aspectFill
            )
            // No resize processor: that would decode at source size first.
            #expect(request.processors.isEmpty, "\(profile)")
            #expect(request.thumbnail == expected, "\(profile)")
        }
    }

    @Test
    func theScrollingProfilesDecodeAtNoMoreThanTwoTimes() {
        #expect(CachedImage.decodeScale(for: .grid) <= 2)
        #expect(CachedImage.decodeScale(for: .shelf) == CachedImage.decodeScale(for: .grid))
        #expect(CachedImage.decodeScale(for: .standard) == CachedImage.decodeScale(for: .grid))
        #expect(CachedImage.decodeScale(for: .high) >= CachedImage.decodeScale(for: .grid))
        #expect(CachedImage.decodeScale(for: .high) <= 3)
    }

    @Test
    func aFrameWithoutASizeStillAsksForABoundedThumbnail() {
        let request = CachedImage.request(
            url: url, width: 0, height: 0, contentMode: .fit, loadProfile: .high
        )
        let onePixel = ImageRequest.ThumbnailOptions(
            size: CGSize(width: 1, height: 1), unit: .pixels, contentMode: .aspectFit
        )
        #expect(request.thumbnail == onePixel)
    }

    @Test
    func detailProfilesGoAheadOfListCells() {
        func priority(_ profile: ImageLoadProfile) -> ImageRequest.Priority {
            CachedImage.request(
                url: url, width: 100, height: 150, contentMode: .fill, loadProfile: profile
            ).priority
        }
        #expect(priority(.standard) == .high)
        #expect(priority(.high) == .high)
        #expect(priority(.shelf) == .normal)
        #expect(priority(.grid) == .normal)
    }

    @Test
    func thePriorityIsNotPartOfTheKeys() {
        // The prefetcher lowers the priority of its copy; that must not cost the match.
        let request = CachedImage.request(
            url: url, width: 100, height: 150, contentMode: .fill, loadProfile: .standard
        )
        var lowered = request
        lowered.priority = .low
        #expect(sameKeys(request, lowered))
    }

    // MARK: - Prefetch batches

    @Test
    func aPrefetchBatchIsCapped() {
        let urls = (0..<(ListImagePrefetch.maxBatch + 12)).map {
            URL(string: "https://img.example.com/posters/\($0).jpg")!
        }
        let requests = ListImagePrefetch.requests(urls: urls, width: 100, height: 150)
        #expect(requests.count == ListImagePrefetch.maxBatch)
        #expect(requests.first?.url == urls.first)
        #expect(ListImagePrefetch.requests(urls: [], width: 100, height: 150).isEmpty)
    }

    @Test
    func theHeadIsAboutTwoScreenfuls() {
        // 3.5 posters across an iPhone: four per screen, eight in the head.
        #expect(ListImagePrefetch.headCount(itemWidth: 100, spacing: 14, containerWidth: 402) == 8)
        // Channel logos are narrower, so more of them fit.
        #expect(ListImagePrefetch.headCount(itemWidth: 58, spacing: 14, containerWidth: 402) == 12)
        // An item that divides the width exactly does not round up to one more.
        #expect(ListImagePrefetch.headCount(itemWidth: 90, spacing: 10, containerWidth: 500) == 10)
    }

    @Test
    func theHeadStaysWithinItsBounds() {
        // One wide card per screen still warms a swipe's worth.
        #expect(ListImagePrefetch.headCount(itemWidth: 300, spacing: 16, containerWidth: 320) == 6)
        // Tiny items on a wide window do not bring the old 32 back.
        #expect(ListImagePrefetch.headCount(itemWidth: 20, spacing: 0, containerWidth: 1366) == 24)
        #expect(ListImagePrefetch.headCount(itemWidth: 1, spacing: 0, containerWidth: 100_000) == 24)

        for itemWidth in stride(from: CGFloat(10), through: 400, by: 13) {
            for containerWidth in stride(from: CGFloat(200), through: 1400, by: 97) {
                let count = ListImagePrefetch.headCount(
                    itemWidth: itemWidth, spacing: 12, containerWidth: containerWidth
                )
                #expect((6...24).contains(count), "\(itemWidth) in \(containerWidth)")
            }
        }
    }

    @Test
    func aDegenerateLayoutFallsBackToTheSmallestHead() {
        #expect(ListImagePrefetch.headCount(itemWidth: 0, spacing: 0, containerWidth: 402) == 6)
        #expect(ListImagePrefetch.headCount(itemWidth: -20, spacing: 4, containerWidth: 402) == 6)
        #expect(ListImagePrefetch.headCount(itemWidth: 100, spacing: 14, containerWidth: 0) == 6)
        #expect(ListImagePrefetch.headCount(itemWidth: .nan, spacing: 14, containerWidth: 402) == 6)
        #expect(ListImagePrefetch.headCount(itemWidth: 100, spacing: 14, containerWidth: .infinity) == 6)
        // A negative spacing is read as none rather than widening the count.
        #expect(
            ListImagePrefetch.headCount(itemWidth: 100, spacing: -50, containerWidth: 402)
                == ListImagePrefetch.headCount(itemWidth: 100, spacing: 0, containerWidth: 402)
        )
    }
}

@Suite("PosterMetrics image sizes")
struct PosterMetricsImageSizeTests {
    private let phone = PosterMetrics(windowSize: CGSize(width: 402, height: 874))
    private let pad = PosterMetrics(windowSize: CGSize(width: 834, height: 1194))

    @Test
    func theShelfRowIsThePosterPlusTheCaptionBlockAsGiven() {
        // The caption block comes in text units and is not scaled with the poster.
        #expect(phone.shelfRowHeight(captionBlock: 38) == phone.shelfPosterHeight + 38)
        #expect(pad.shelfRowHeight(captionBlock: 38) == pad.shelfPosterHeight + 38)
        #expect(phone.shelfRowHeight(captionBlock: 0) == phone.shelfPosterHeight)
    }

    @Test
    func theFixedShelfHeightIsUnchanged() {
        #expect(phone.shelfRowTotalHeight == 182)
        #expect(pad.shelfRowTotalHeight == 364)
    }

    @Test
    func theLogoDecodeSideIsCappedInPixels() {
        let scale = CachedImage.decodeScale(for: .grid)
        for metrics in [phone, pad] {
            let side = metrics.logoDecodeSide
            #expect(side > 0)
            #expect(side <= metrics.liveGridIconSize)
            #expect((side * scale).rounded(.up) <= PosterMetrics.logoDecodePixelCap)
            #expect(side == min(metrics.liveGridIconSize, (256 / scale).rounded(.down)))
        }
        // The phone grid tile is below the cap and decodes at its own size; the iPad tile
        // would be 360 px at 2x and is held at the cap.
        #expect(phone.logoDecodeSide == phone.liveGridIconSize)
        #expect(pad.logoDecodeSide < pad.liveGridIconSize)
    }
}
