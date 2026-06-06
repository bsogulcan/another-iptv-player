import Foundation
import SwiftUI
import Nuke
import NukeUI
import UIKit

/// Uzak kanal ikonu / poster URL’leri çoğu zaman ölü veya TLS hatalı; `URLSession.shared` fırtınası CFNetwork’ü konsola doldurur.
/// Tamamen susturulamaz, ancak host başına bağlantı ve zaman aşımı ile satır sayısı ve gecikme azalır.
enum IPTVRemoteImagePipeline {
    private static let installLock = NSLock()
    private static var didInstall = false

    static func installAsShared() {
        installLock.lock()
        defer { installLock.unlock() }
        guard !didInstall else { return }
        didInstall = true

        var urlConf = DataLoader.defaultConfiguration
        urlConf.httpMaximumConnectionsPerHost = 4
        urlConf.timeoutIntervalForRequest = 10
        urlConf.timeoutIntervalForResource = 20
        urlConf.waitsForConnectivity = false
        let loader = DataLoader(configuration: urlConf)

        // Bellek önbelleğini sınırla: sınırsız bırakmak tüm RAM'i doldurabiliyor
        let memoryCache = ImageCache()
        memoryCache.costLimit = 150 * 1024 * 1024  // 150 MB
        memoryCache.countLimit = 1500

        ImagePipeline.shared = ImagePipeline {
            $0.dataLoader = loader
            $0.imageCache = memoryCache
            if #available(iOS 15.0, *) {
                $0.isUsingPrepareForDisplay = true
            }
        }
    }
}

/// Nuke `LazyImage` + piksel resize; liste/grid kaydırmasında `grid` veya `shelf` kullan.
enum ImageLoadProfile: Equatable, Sendable {
    /// Tekil / header: hafif animasyon, görünümden çıkınca istek iptal.
    case standard
    /// Yatay raf: küçük decode, kaybolunca iptal yok.
    case shelf
    /// Uzun grid / liste: retina decode, iptal yok.
    case grid
    /// Büyük görseller / backdrop: Downsampling yok veya çok yüksek.
    case high
}

struct CachedImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 8
    var contentMode: SwiftUI.ContentMode = .fit
    var iconName: String = "photo"
    var loadProfile: ImageLoadProfile = .standard

    var body: some View {
        Group {
            if let url {
                // Özel `transaction` aynı frame’de birden fazla LazyImageContext güncellemesi uyarısına yol açabiliyor; animasyon üst `Group` ile.
                LazyImage(request: makeRequest(url: url)) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    } else {
                        placeholder
                    }
                }
                .onDisappear(loadProfile == .standard ? .cancel : nil)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                placeholder
            }
        }
        .transaction { t in
            if loadProfile == .standard {
                t.animation = .easeIn(duration: 0.12)
            } else {
                t.animation = nil
            }
        }
    }

    private func downsamplePixelSize() -> CGSize {
        switch loadProfile {
        case .shelf:
            // Yatay raflarda önizleme: 2x yeterli, 3x gereksiz bellek tüketir
            let s = min(UIScreen.main.scale, 2)
            return CGSize(width: ceil(width * s), height: ceil(height * s))
        case .standard, .grid:
            // Grid / liste: 2x görsel olarak 3x'ten ayırt edilemez, %44 daha az bellek
            let s = min(UIScreen.main.scale, 2)
            return CGSize(width: ceil(width * s), height: ceil(height * s))
        case .high:
            // Hero / backdrop: büyük ekranda 3x kalite korunur
            let s = min(UIScreen.main.scale, 3)
            return CGSize(width: ceil(width * s), height: ceil(height * s))
        }
    }

    private func makeRequest(url: URL) -> ImageRequest {
        let target = downsamplePixelSize()
        let nukeMode: ImageProcessingOptions.ContentMode = (contentMode == .fill) ? .aspectFill : .aspectFit
        return ImageRequest(
            url: url,
            processors: [
                ImageProcessors.Resize(
                    size: target,
                    unit: .pixels,
                    contentMode: nukeMode,
                    crop: false,
                    upscale: false
                )
            ]
        )
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.systemGray6))
            Image(systemName: iconName)
                .font(.system(size: min(width, height) * 0.28, weight: .light))
                .foregroundStyle(.quaternary)
        }
        .frame(width: width, height: height)
    }
}
