import AppKit
import AVFoundation
import CoreMedia
import CoreVideo

/// macOS varyantı (iOS PixelBufferDisplayView.swift'ten port).
/// Video karelerini `AVSampleBufferDisplayLayer`'a aktarır. macOS'ta NSView'in
/// `makeBackingLayer` ile layer-host yapılması iOS'taki `layerClass` override'ının karşılığı.
public final class PixelBufferDisplayView: NSView {
  override public func makeBackingLayer() -> CALayer {
    AVSampleBufferDisplayLayer()
  }

  private var cachedDisplayLayer: AVSampleBufferDisplayLayer!

  public var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
    cachedDisplayLayer
  }

  private var cachedFormatDescription: CMFormatDescription?
  private var cachedFormatWidth: Int32 = 0
  private var cachedFormatHeight: Int32 = 0

  private let displayQueue = DispatchQueue(
    label: "another.iptv.PixelBufferDisplayView.display",
    qos: .userInteractive
  )

  override public init(frame: NSRect) {
    super.init(frame: frame)
    commonInit()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    commonInit()
  }

  private func commonInit() {
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    // swiftlint:disable:next force_cast
    cachedDisplayLayer = (layer as! AVSampleBufferDisplayLayer)
    cachedDisplayLayer.backgroundColor = NSColor.black.cgColor
    cachedDisplayLayer.videoGravity = .resizeAspect
  }

  public func setVideoGravity(_ gravity: AVLayerVideoGravity) {
    displayQueue.async { [weak self] in
      guard let self else { return }
      if self.sampleBufferDisplayLayer.videoGravity != gravity {
        self.sampleBufferDisplayLayer.videoGravity = gravity
      }
    }
  }

  public func enqueuePixelBuffer(_ pixelBuffer: CVPixelBuffer, flipVerticalForOpenGL: Bool) {
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
    guard sbdl.isReadyForMoreMediaData else { return }
    sbdl.enqueue(sampleBuffer)
  }

  private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
    let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
    let height = Int32(CVPixelBufferGetHeight(pixelBuffer))
    guard width > 1, height > 1 else { return nil }

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
