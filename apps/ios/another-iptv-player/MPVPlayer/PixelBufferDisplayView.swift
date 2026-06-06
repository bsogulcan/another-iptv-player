import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

/// Video karelerini `AVSampleBufferDisplayLayer`'a aktarır. Hem normal inline gösterim
/// hem de `AVPictureInPictureController` sample buffer content source için kullanılır.
///
/// Tasarım notu: Eski yol `CVPixelBuffer` → `CGImage` → `UIImage` → `UIImageView.image`
/// idi. Her frame için 8 MB (1080p) kopyalanıyor, CA commit tetikleniyor ve arka planda
/// PiP açıkken bellek bant genişliği + allocator baskısı termal kısıtlamayla birleşerek
/// frame drop'a yol açıyordu. `AVSampleBufferDisplayLayer` Apple'ın PiP ve düşük gecikmeli
/// video görüntüleme için tasarladığı native yoldur; frame pacing, upload ve PiP penceresi
/// compositing'i sistem tarafından yönetilir.
///
/// Senkronizasyon: tüm layer erişimi bir tekli serial dispatch queue üzerinden yapılır.
/// mpv callback thread'i bloklanmaz (`async` hand-off) ve tüm ordering queue tarafından
/// garanti edilir. `NSLock` + `makeSampleBuffer` içinde ikinci lock alma yolu kaldırıldı.
public final class PixelBufferDisplayView: UIView {
  override public class var layerClass: AnyClass {
    AVSampleBufferDisplayLayer.self
  }

  /// `UIView.layer`'a yalnız main thread'den erişilebilir (UIKit). Referans init'te
  /// (main thread) bir kez alınıp cache'lenir; `displayQueue` blokları bu cache'i
  /// kullanır, böylece `-[UIView layer]` arka plan thread'inden çağrılmaz.
  private var cachedDisplayLayer: AVSampleBufferDisplayLayer!

  public var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
    cachedDisplayLayer
  }

  /// `makeSampleBuffer` içindeki format cache yalnızca bu queue'dan erişilir —
  /// ayrıca lock gerekmez.
  private var cachedFormatDescription: CMFormatDescription?
  private var cachedFormatWidth: Int32 = 0
  private var cachedFormatHeight: Int32 = 0

  /// Tüm layer etkileşimi bu queue üzerinden. `userInteractive` çünkü PiP frame timing
  /// kritik; `target: .main` kullanılmaz, main thread'i bloklamasın. Static tek instance:
  /// aynı anda birden fazla `PixelBufferDisplayView` açık olması beklenmeyen durum;
  /// ortak bir queue sıralamayı korur.
  private let displayQueue = DispatchQueue(
    label: "another.iptv.PixelBufferDisplayView.display",
    qos: .userInteractive
  )

  override public init(frame: CGRect) {
    super.init(frame: frame)
    commonInit()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    commonInit()
  }

  private func commonInit() {
    isOpaque = true
    backgroundColor = .black
    // `layerClass` garantisi cast'i güvenli kılar. Main thread'de (init) bir kez alınır.
    // swiftlint:disable:next force_cast
    cachedDisplayLayer = (layer as! AVSampleBufferDisplayLayer)
    cachedDisplayLayer.backgroundColor = UIColor.black.cgColor
    cachedDisplayLayer.videoGravity = .resizeAspect
  }

  public func setVideoContentMode(_ mode: UIView.ContentMode) {
    let gravity: AVLayerVideoGravity
    switch mode {
    case .scaleAspectFit: gravity = .resizeAspect
    case .scaleAspectFill: gravity = .resizeAspectFill
    case .scaleToFill: gravity = .resize
    default: gravity = .resizeAspect
    }
    displayQueue.async { [weak self] in
      guard let self else { return }
      if self.sampleBufferDisplayLayer.videoGravity != gravity {
        self.sampleBufferDisplayLayer.videoGravity = gravity
      }
    }
  }

  /// mpv callback herhangi bir thread'den gelebilir; hand-off anlık dönmelidir.
  public func enqueuePixelBuffer(_ pixelBuffer: CVPixelBuffer, flipVerticalForOpenGL: Bool) {
    // `NativeVideoOutput` daima flip=false gönderir; flip=true beklenmeyen bir durum,
    // sessizce düş — display layer'a yanlış yönlü frame vermeyelim.
    guard !flipVerticalForOpenGL else { return }
    displayQueue.async { [weak self] in
      self?.processEnqueue(pixelBuffer)
    }
  }

  public func flush() {
    displayQueue.async { [weak self] in
      self?.sampleBufferDisplayLayer.flushAndRemoveImage()
    }
  }

  // MARK: - displayQueue only

  private func processEnqueue(_ pixelBuffer: CVPixelBuffer) {
    guard let sampleBuffer = makeSampleBuffer(from: pixelBuffer) else { return }
    let sbdl = sampleBufferDisplayLayer
    if sbdl.status == .failed {
      sbdl.flush()
    }
    // Layer backlog'u birikirse düşür — bir sonraki frame zaten yolda.
    guard sbdl.isReadyForMoreMediaData else { return }
    sbdl.enqueue(sampleBuffer)
  }

  private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
    let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
    let height = Int32(CVPixelBufferGetHeight(pixelBuffer))
    guard width > 1, height > 1 else { return nil }

    // Format description boyut değiştiğinde yenilenir; cache serial queue'ya özel.
    if cachedFormatDescription == nil
      || cachedFormatWidth != width
      || cachedFormatHeight != height {
      var newFormat: CMFormatDescription?
      let status = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &newFormat
      )
      guard status == noErr, let newFormat else { return nil }
      cachedFormatDescription = newFormat
      cachedFormatWidth = width
      cachedFormatHeight = height
    }
    guard let formatDescription = cachedFormatDescription else { return nil }

    // Timing mpv tarafında; `kCMSampleAttachmentKey_DisplayImmediately` ile layer'a kuyrukta bekletmez.
    var timingInfo = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: .invalid,
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    let status = CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: formatDescription,
      sampleTiming: &timingInfo,
      sampleBufferOut: &sampleBuffer
    )
    guard status == noErr, let sampleBuffer else { return nil }

    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
       CFArrayGetCount(attachments) > 0 {
      let dict = unsafeBitCast(
        CFArrayGetValueAtIndex(attachments, 0),
        to: CFMutableDictionary.self
      )
      CFDictionarySetValue(
        dict,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
      )
    }
    return sampleBuffer
  }
}
