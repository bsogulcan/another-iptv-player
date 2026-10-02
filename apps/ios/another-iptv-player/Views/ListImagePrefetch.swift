import Foundation
import Nuke
import SwiftUI
import UIKit

enum ListImagePrefetch {
    static let maxBatch = 48

    private static let prefetcher = ImagePrefetcher(
        pipeline: .shared,
        destination: .memoryCache,
        maxConcurrentRequestCount: 3
    )

    /// Warms the cache for a bounded number of URLs ahead of a grid or a shelf.
    ///
    /// The cache keys contain the decode size and the content mode. A prefetch request
    /// that is not built exactly like the render request never hits, and every image is
    /// decoded twice. So the caller passes what its card gives `CachedImage` (the decode
    /// size where the card overrides it, otherwise width / height, plus contentMode and
    /// loadProfile) and the requests come from `CachedImage.request`.
    ///
    /// Pair it with `stop` when the row or grid goes away: a prefetch that is not stopped
    /// runs to the end, long after a fling has left its images behind.
    static func start(
        urls: [URL],
        width: CGFloat,
        height: CGFloat,
        contentMode: SwiftUI.ContentMode = .fit,
        loadProfile: ImageLoadProfile = .grid
    ) {
        let batch = requests(
            urls: urls, width: width, height: height, contentMode: contentMode, loadProfile: loadProfile
        )
        guard !batch.isEmpty else { return }
        prefetcher.startPrefetching(with: batch)
    }

    /// Cancels what `start` queued for the same arguments. No state has to be kept between
    /// the two calls: requests are matched by URL and decode options, so building them
    /// again is enough. A cell that is on screen and waits for one of these images keeps
    /// loading it; only the prefetcher lets go.
    static func stop(
        urls: [URL],
        width: CGFloat,
        height: CGFloat,
        contentMode: SwiftUI.ContentMode = .fit,
        loadProfile: ImageLoadProfile = .grid
    ) {
        let batch = requests(
            urls: urls, width: width, height: height, contentMode: contentMode, loadProfile: loadProfile
        )
        guard !batch.isEmpty else { return }
        prefetcher.stopPrefetching(with: batch)
    }

    /// The requests `start` and `stop` act on: at most `maxBatch`, each one equal to what
    /// a `CachedImage` with the same arguments renders.
    static func requests(
        urls: [URL],
        width: CGFloat,
        height: CGFloat,
        contentMode: SwiftUI.ContentMode = .fit,
        loadProfile: ImageLoadProfile = .grid
    ) -> [ImageRequest] {
        urls.prefix(maxBatch).map {
            CachedImage.request(
                url: $0,
                width: width,
                height: height,
                contentMode: contentMode,
                loadProfile: loadProfile
            )
        }
    }

    static let minHeadCount = 6
    static let maxHeadCount = 24

    /// How many leading items of a horizontal shelf are worth prefetching: about two
    /// screenfuls, which is what one swipe reaches. More than that is downloaded and
    /// decoded for nobody and pushes images the user did see out of the memory cache.
    static func headCount(itemWidth: CGFloat, spacing: CGFloat, containerWidth: CGFloat) -> Int {
        let stride = itemWidth + max(0, spacing)
        guard stride > 0, containerWidth > 0, stride.isFinite, containerWidth.isFinite else {
            return minHeadCount
        }
        let perScreen = (containerWidth / stride).rounded(.up)
        guard perScreen < CGFloat(maxHeadCount) else { return maxHeadCount }
        return min(maxHeadCount, max(minHeadCount, Int(perScreen) * 2))
    }
}
