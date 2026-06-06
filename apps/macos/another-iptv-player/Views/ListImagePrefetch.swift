import AppKit
import Foundation
import Nuke

enum ListImagePrefetch {
    static let maxBatch = 48

    private static let prefetcher = ImagePrefetcher(
        pipeline: .shared,
        destination: .memoryCache,
        maxConcurrentRequestCount: 3
    )

    /// Grid veya raf öncesi sınırlı sayıda URL’yi önbelleğe alır.
    /// - Parameter isShelf: `true` ise raf (shelf) profiliyle decode edilir; cache key render ile uyuşur.
    static func start(urls: [URL], posterMetrics: PosterMetrics? = nil, isShelf: Bool = false) {
        let slice = Array(urls.prefix(maxBatch))
        guard !slice.isEmpty else { return }
        let m = posterMetrics ?? PosterMetrics(windowSize: (NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)))
        let size = isShelf ? m.prefetchShelfDecodePixelSize() : m.prefetchCategoryDecodePixelSize()
        let processor = ImageProcessors.Resize(
            size: size,
            unit: .pixels,
            contentMode: .aspectFill,
            crop: false,
            upscale: false
        )
        let requests = slice.map { ImageRequest(url: $0, processors: [processor]) }
        prefetcher.startPrefetching(with: requests)
    }
}
