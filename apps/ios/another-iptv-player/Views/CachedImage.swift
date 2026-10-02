import Foundation
import Network
import SwiftUI
import Nuke
import NukeUI
import UIKit

/// Uzak kanal ikonu / poster URL’leri çoğu zaman ölü veya TLS hatalı; `URLSession.shared` fırtınası CFNetwork’ü konsola doldurur.
/// Tamamen susturulamaz, ancak host başına bağlantı ve zaman aşımı ile satır sayısı ve gecikme azalır.
enum IPTVRemoteImagePipeline {
    private static let installLock = NSLock()
    private static var didInstall = false

    /// Directory name of the thumbnail cache inside Caches, and its budget. The system may
    /// purge Caches; the entries are only ever a shortcut past a download and a decode.
    static let thumbnailCacheName = "image-thumbnails"
    static let thumbnailCacheSizeLimit = 300 * 1024 * 1024

    /// Remembers hosts that stopped answering so they cannot hold the download slots.
    static let hostBreaker = ImageHostBreaker()

    private static var foregroundObserver: NSObjectProtocol?
    private static var pathMonitor: NWPathMonitor?

    static func installAsShared() {
        installLock.lock()
        defer { installLock.unlock() }
        guard !didInstall else { return }
        didInstall = true

        let urlConf = DataLoader.defaultConfiguration
        urlConf.httpMaximumConnectionsPerHost = 4
        urlConf.timeoutIntervalForRequest = 10
        urlConf.timeoutIntervalForResource = 20
        urlConf.waitsForConnectivity = false
        let loader = DataLoader(configuration: urlConf)

        // Bellek önbelleğini sınırla: sınırsız bırakmak tüm RAM'i doldurabiliyor
        let memoryCache = ImageCache()
        memoryCache.costLimit = 150 * 1024 * 1024  // 150 MB
        memoryCache.countLimit = 1500

        let thumbnails = try? DataCache(name: thumbnailCacheName)
        thumbnails?.sizeLimit = thumbnailCacheSizeLimit

        ImagePipeline.shared = makePipeline(
            dataLoader: loader,
            imageCache: memoryCache,
            thumbnailCache: thumbnails,
            hostBreaker: hostBreaker,
            hostReopened: { ImageHostReopenings.announce() }
        )

        forgetBlockedHostsOnConnectivityChange()
    }

    /// The app's pipeline around the given parts; `installAsShared` passes the real ones.
    ///
    /// Downsampled images are kept in `thumbnailCache`, keyed by URL and decode size, so a
    /// relaunch or a trimmed memory cache costs a small file read instead of a download
    /// and a full-size decode, and no longer depends on the host's cache headers.
    /// Originals stay in the loader's URLCache (see `IPTVImagePipelineDelegate.willCache`).
    ///
    /// `hostReopened` is called, on any thread, whenever a request that `hostBreaker`
    /// refused would get through. `uptime` is the breaker's clock.
    static func makePipeline(
        dataLoader: any DataLoading,
        imageCache: (any ImageCaching)?,
        thumbnailCache: (any DataCaching)?,
        hostBreaker: ImageHostBreaker,
        hostReopened: @escaping @Sendable () -> Void = {},
        uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) -> ImagePipeline {
        let delegate = IPTVImagePipelineDelegate(breaker: hostBreaker, reopened: hostReopened, uptime: uptime)
        return ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = thumbnailCache
            $0.dataCachePolicy = .automatic
            // Requests downsample while decoding, so that work moved from the processing
            // queue (two at a time) to this one, which defaults to one.
            $0.imageDecodingQueue = TaskQueue(maxConcurrentOperationCount: 2)
            if #available(iOS 15.0, *) {
                $0.isUsingPrepareForDisplay = true
            }
        }
    }

    /// A timeout on the old connection says nothing about the new one, and three of them
    /// on a train or behind a captive portal would otherwise keep a healthy host blocked
    /// after the network is back.
    private static func forgetBlockedHostsOnConnectivityChange() {
        let breaker = hostBreaker
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            if breaker.reset() { ImageHostReopenings.announce() }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { _ in
            if breaker.reset() { ImageHostReopenings.announce() }
        }
        monitor.start(queue: DispatchQueue(label: "image-host-breaker.path", qos: .utility))
        pathMonitor = monitor
    }
}

/// Pipeline hooks for the host breaker and for what goes into the thumbnail cache.
private nonisolated final class IPTVImagePipelineDelegate: ImagePipeline.Delegate {
    private let breaker: ImageHostBreaker
    private let reopened: @Sendable () -> Void
    private let uptime: @Sendable () -> TimeInterval

    init(
        breaker: ImageHostBreaker,
        reopened: @escaping @Sendable () -> Void,
        uptime: @escaping @Sendable () -> TimeInterval
    ) {
        self.breaker = breaker
        self.reopened = reopened
        self.uptime = uptime
    }

    /// Runs once the request holds a download slot; throwing gives the slot back at once.
    func willLoadData(
        for request: ImageRequest,
        urlRequest: URLRequest,
        pipeline: ImagePipeline
    ) async throws -> URLRequest {
        if let url = urlRequest.url, let host = ImageHostBreaker.hostKey(for: url),
           !breaker.allowsLoad(host: host, url: url.absoluteString, now: uptime()) {
            throw ImageHostBlocked(host: host)
        }
        return urlRequest
    }

    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard case .finished(let result) = event, let url = task.request.url else { return }
        // Progress events reach the task before the result does, so this tells a host
        // that sent nothing from a download that was under way when its time ran out.
        let receivedBytes = task.currentProgress.completed > 0
        switch breaker.record(result, receivedBytes: receivedBytes, for: url, now: uptime()) {
        case .blocked:
            // Without a trace, logos missing for this reason look like any other failure.
            let host = ImageHostBreaker.hostKey(for: url) ?? "?"
            let window = breaker.policy.blockWindow
            Log.info("ImagePipeline", "image host \(host) keeps timing out, skipped for \(Int(window)) s")
            // Nothing asks again by itself when the window ends, so the cells that were
            // refused are told. One of them becomes the probe; the margin keeps the
            // wake-up from landing on the last instant of the window.
            let reopened = self.reopened
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + window + 0.25) {
                reopened()
            }
        case .reopened:
            reopened()
        case .none:
            break
        }
    }

    /// `image` is nil when the pipeline offers the original download. A request without
    /// processors makes it do that, and every thumbnail request is one, so without this
    /// the disk budget would fill with full-size files that URLCache already holds.
    func willCache(
        data: Data,
        image: ImageContainer?,
        for request: ImageRequest,
        pipeline: ImagePipeline,
        completion: @escaping (Data?) -> Void
    ) {
        completion(image == nil ? nil : data)
    }
}

/// How an image is decoded and how its request behaves while the view is off screen.
/// Use `grid` or `shelf` inside anything that scrolls.
enum ImageLoadProfile: Equatable, Sendable {
    /// Single image / header: loaded ahead of list cells, cancelled when it disappears.
    case standard
    /// Horizontal shelf: the request survives a disappear at low priority.
    case shelf
    /// Long grid / list: the request survives a disappear at low priority.
    case grid
    /// Large images / backdrop: decoded at up to 3x, loaded ahead of list cells, never cancelled.
    case high

    fileprivate var cancelsOnDisappear: Bool { self == .standard }

    /// Priority while the view is on screen. Detail images go ahead of whatever a grid
    /// behind them still has queued.
    fileprivate var visiblePriority: ImageRequest.Priority {
        switch self {
        case .standard, .high: return .high
        case .shelf, .grid: return .normal
        }
    }
}

struct CachedImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 8
    var contentMode: SwiftUI.ContentMode = .fit
    var iconName: String = "photo"
    var loadProfile: ImageLoadProfile = .standard
    /// Decode size in points when it should differ from the layout size, so that the same
    /// artwork shares one cache entry between screens that draw it at different sizes.
    var decodeWidth: CGFloat? = nil
    var decodeHeight: CGFloat? = nil
    /// Keeps the rounded tile under a loaded `.fit` image and insets the image a little.
    /// For logos, which are often transparent or far from square and otherwise give every
    /// cell in a row a different outline. No effect on `.fill`.
    var showsTile: Bool = false
    /// Decorative images are hidden from VoiceOver: the title next to them says the same.
    /// Turn it off where the image itself is the control and give it a label there.
    var isDecorative: Bool = true

    /// `false` brings back the NukeUI `LazyImage` body, which reloads on every appear and
    /// cannot lower the priority of off-screen cells. Kept as a one-line way back.
    private static let usesFetchImage = true

    var body: some View {
        Group {
            if let url {
                if Self.usesFetchImage {
                    FetchImageBody(spec: self, url: url)
                } else {
                    LazyImageBody(spec: self, url: url)
                }
            } else {
                content(image: nil)
            }
        }
        // One element whatever is inside, so a label added by the caller covers the
        // placeholder too (its symbol would otherwise be read as "Photo" or "TV").
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityHidden(isDecorative)
    }

    /// The request this view loads for `url`.
    func makeRequest(url: URL) -> ImageRequest {
        Self.request(
            url: url,
            width: width,
            height: height,
            contentMode: contentMode,
            loadProfile: loadProfile,
            decodeWidth: decodeWidth,
            decodeHeight: decodeHeight
        )
    }

    fileprivate var targetPixelSize: CGSize {
        Self.decodePixelSize(
            width: decodeWidth ?? width,
            height: decodeHeight ?? height,
            loadProfile: loadProfile
        )
    }

    /// The one place an image request is built. `ListImagePrefetch` goes through it too:
    /// the cache keys contain the decode size and the content mode, so a prefetch only
    /// warms a cell if both requests come from here with the same arguments.
    ///
    /// The image is downsampled while it is decoded (`thumbnail`), not decoded at source
    /// size and redrawn smaller. `decodeWidth` / `decodeHeight` replace the layout size
    /// for that; passing the decode size as `width` / `height` instead yields the same
    /// request, which is what a prefetch call does.
    static func request(
        url: URL,
        width: CGFloat,
        height: CGFloat,
        contentMode: SwiftUI.ContentMode,
        loadProfile: ImageLoadProfile,
        decodeWidth: CGFloat? = nil,
        decodeHeight: CGFloat? = nil
    ) -> ImageRequest {
        let target = decodePixelSize(
            width: decodeWidth ?? width,
            height: decodeHeight ?? height,
            loadProfile: loadProfile
        )
        let nukeMode: ImageProcessingOptions.ContentMode = (contentMode == .fill) ? .aspectFill : .aspectFit
        // The priority is part of neither the cache key nor the task key, and the
        // prefetcher overrides it, so it cannot make prefetch and render requests differ.
        var request = ImageRequest(url: url, priority: loadProfile.visiblePriority)
        request.thumbnail = ImageRequest.ThumbnailOptions(size: target, unit: .pixels, contentMode: nukeMode)
        return request
    }

    /// Screen scale an image is decoded at. Shared by everything that derives a decode
    /// size, so that prefetch and render agree.
    static func decodeScale(for loadProfile: ImageLoadProfile) -> CGFloat {
        switch loadProfile {
        case .shelf, .standard, .grid:
            // 2x görsel olarak 3x'ten ayırt edilemez, %44 daha az bellek
            return min(UIScreen.main.scale, 2)
        case .high:
            // Hero / backdrop: büyük ekranda 3x kalite korunur
            return min(UIScreen.main.scale, 3)
        }
    }

    private static func decodePixelSize(width: CGFloat, height: CGFloat, loadProfile: ImageLoadProfile) -> CGSize {
        let s = decodeScale(for: loadProfile)
        // Never below one pixel: a frame that has no size yet must not turn into an
        // unbounded thumbnail request.
        return CGSize(width: max(1, ceil(width * s)), height: max(1, ceil(height * s)))
    }

    /// Fade for an image that arrives from disk or the network; a memory hit is shown
    /// without it. The one place to return nil for `.shelf` / `.grid` should many
    /// simultaneous fades ever cost frames during a fling.
    fileprivate static func fade(for loadProfile: ImageLoadProfile) -> Animation? {
        .easeOut(duration: 0.18)
    }

    // MARK: - Drawing

    private var tile: some View {
        Rectangle().fill(Color(.systemGray6))
    }

    private var glyph: some View {
        Image(systemName: iconName)
            .font(.system(size: min(width, height) * 0.28, weight: .light))
            .foregroundStyle(.quaternary)
    }

    /// Tile, glyph and image for one loading state; `nil` draws the placeholder.
    fileprivate func content(image: Image?) -> some View {
        let insetsImage = showsTile && contentMode == .fit
        return ZStack {
            // A `.fill` image covers the tile completely, so the tile stays and only the
            // image fades in over it. A `.fit` image is usually a logo with transparency:
            // there the tile goes away with the placeholder unless the caller asked for it.
            if image == nil || contentMode == .fill || insetsImage {
                tile
            }
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    // Artwork keeps its colours under Smart Invert; the tile and the
                    // glyph are interface and still invert.
                    .accessibilityIgnoresInvertColors()
                    .padding(insetsImage ? min(width, height) * 0.1 : 0)
                    .transition(.opacity)
            } else {
                glyph
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Loading

/// Identity of what is on screen: when it changes, the image has to be loaded again.
private nonisolated struct CachedImageRequestKey: Equatable {
    let url: URL
    let pixelSize: CGSize
    let contentMode: SwiftUI.ContentMode
}

/// Drives a `FetchImage` directly instead of going through `LazyImage`, for two things
/// `LazyImage` cannot do. It reloads on every appear, so after the memory cache was
/// trimmed (every time the app goes to the background) a pop or a tab switch turned
/// loaded cells back into placeholders; here an image that is already shown is kept.
/// And its "lower priority on disappear" never raises the priority again, which left
/// cells that scrolled back stuck at the bottom of the queue; here it is raised on
/// every appear.
private struct FetchImageBody: View {
    let spec: CachedImage
    let url: URL

    @StateObject private var model = FetchImage()
    /// The previous bitmap of the same URL, kept on screen while another decode size of
    /// it loads (rotation, a resized window).
    @State private var carried: ImageContainer?
    /// `ImageHostReopenings.epoch` when the current load started. Never read in `body`.
    @State private var epochAtLoad = 0
    @Environment(\.scenePhase) private var scenePhase

    private var requestKey: CachedImageRequestKey {
        CachedImageRequestKey(url: url, pixelSize: spec.targetPixelSize, contentMode: spec.contentMode)
    }

    /// The reopening count while this cell is a placeholder because the host breaker
    /// refused its request, nil otherwise. Reading the count only in that state is what
    /// keeps every other cell from updating when it changes.
    private var refusalEpoch: Int? {
        guard case .failure(let error) = model.result, ImageHostBlocked.isCause(of: error) else { return nil }
        return ImageHostReopenings.shared.epoch
    }

    var body: some View {
        spec.content(image: (model.imageContainer ?? carried).map { Image(uiImage: $0.image) })
            .onAppear { appear() }
            .onDisappear { disappear() }
            .onChange(of: requestKey) { old, new in
                reload(keepingCurrentImage: old.url == new.url)
            }
            .onChange(of: model.imageContainer != nil) { _, isLoaded in
                if isLoaded { carried = nil }
            }
            .onChange(of: scenePhase) { _, phase in
                // A cell that failed while offline would otherwise stay a placeholder
                // until it is scrolled away and back.
                if phase == .active, case .failure = model.result {
                    load()
                }
            }
            .onChange(of: refusalEpoch) { _, epoch in
                // A refused request is not queued, so the cell asks again once the host
                // may be open. Comparing with the count at load time, not with the old
                // value, also covers a host that reopened while the refusal was still
                // on its way here, and stops a second refusal from asking in a loop.
                if let epoch, epoch != epochAtLoad {
                    load()
                }
            }
    }

    private func appear() {
        model.transaction = Transaction(animation: CachedImage.fade(for: spec.loadProfile))
        // Also raises a request that is still running from before the cell left the screen.
        model.priority = spec.loadProfile.visiblePriority
        // What is already shown is kept, and a request that is still running is not
        // started over. A load that failed is tried again.
        guard model.imageContainer == nil, !model.isLoading else { return }
        load()
    }

    private func disappear() {
        if spec.loadProfile.cancelsOnDisappear {
            // `cancel()` alone leaves `isLoading` set for good, and the next appear would
            // wait for a request that no longer exists. `reset()` clears it, but drops
            // the image as well, so it is only used when there is no image to keep.
            if model.imageContainer == nil {
                model.reset()
            } else {
                model.cancel()
            }
        } else {
            // The cell may be back in a moment, so the request lives on, behind the
            // requests of what is on screen now. Tearing the cell down cancels it.
            model.priority = .low
        }
    }

    private func reload(keepingCurrentImage: Bool) {
        carried = keepingCurrentImage ? (model.imageContainer ?? carried) : nil
        load()
        // A memory hit replaced it within the same call.
        if model.imageContainer != nil { carried = nil }
    }

    private func load() {
        let epoch = ImageHostReopenings.shared.epoch
        if epochAtLoad != epoch { epochAtLoad = epoch }
        // The synchronous part of a load (dropping the old image, a memory hit) must not
        // pick up an animation that happens to run around the cell. Only an image that
        // arrives later fades, through the model's own transaction.
        var immediate = Transaction(animation: nil)
        immediate.disablesAnimations = true
        withTransaction(immediate) {
            model.load(spec.makeRequest(url: url))
        }
    }
}

/// The NukeUI `LazyImage` body this view used before `FetchImageBody`; see
/// `CachedImage.usesFetchImage`. A change of decode size alone does not reload here,
/// because `LazyImage` does not compare the thumbnail options of two requests.
private struct LazyImageBody: View {
    let spec: CachedImage
    let url: URL

    @State private var failed = false
    /// The failure on screen is the host breaker refusing the request.
    @State private var refused = false
    /// `ImageHostReopenings.epoch` when the current load started.
    @State private var epochAtLoad = 0
    @State private var retryToken = 0
    @Environment(\.scenePhase) private var scenePhase

    /// See `FetchImageBody.refusalEpoch`.
    private var refusalEpoch: Int? {
        refused ? ImageHostReopenings.shared.epoch : nil
    }

    var body: some View {
        LazyImage(
            request: spec.makeRequest(url: url),
            transaction: Transaction(animation: CachedImage.fade(for: spec.loadProfile))
        ) { state in
            spec.content(image: state.image)
        }
        // No disappear behaviour for the scrolling profiles (deliberate): `.lowerPriority`
        // leaves the request of a cell that scrolls back stuck at `.veryLow`, so posters
        // never loaded. The request lives on until the cell is torn down.
        .onDisappear(spec.loadProfile.cancelsOnDisappear ? .cancel : nil)
        .onStart { _ in
            epochAtLoad = ImageHostReopenings.shared.epoch
        }
        .onCompletion { result in
            // Every appear loads again, so a cell that failed once can succeed later;
            // the flags describe the last load, not any load.
            switch result {
            case .success:
                failed = false
                refused = false
            case .failure(let error):
                failed = true
                refused = ImageHostBlocked.isCause(of: error)
            }
        }
        // Remounting is the only way to make a `LazyImage` load again.
        .id(retryToken)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, failed { remount() }
        }
        .onChange(of: refusalEpoch) { _, epoch in
            if let epoch, epoch != epochAtLoad { remount() }
        }
    }

    private func remount() {
        failed = false
        refused = false
        retryToken += 1
    }
}
