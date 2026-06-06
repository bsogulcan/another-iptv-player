import CoreVideo
import Foundation

/// Xcode konsolunda filtre: `MPVPlayer`
///
/// **Kanal zapping / frame drop debug protokolü**
/// 1. `channelZappingTraceEnabled = true` yapın.
/// 2. Konsol filtresi: `MPVPlayer.zap` (dar) veya `MPVPlayer` (geniş: `NativeOut.*`, `Display.*`, `Surface.*` dahil).
/// 3. Senaryo: canlı tam ekran → Kanallar → listede hızlı gezinme; gerekirse geri dönüp ana akışı izleyin.
/// 4. İzlenecekler: `zap` sırası (yük/commit), ardından `NativeOut.nopb` / `NativeOut.size0`, `Display.createCGImage`,
///    `Surface.weakView`, ve oynatıcı debug’unda mpv `dropped-frame` / `delayed-frame`.
enum MPVPlayerVideoLog {
  /// `true`: kanal vurgusu ve mini önizleme `play` yollarında `MPVPlayer.zap` logları.
  static var channelZappingTraceEnabled = false

  static func zapIfEnabled(_ message: @autoclosure () -> String) {
    guard channelZappingTraceEnabled else { return }
    always("zap", message())
  }
  private final class State {
    let lock = NSLock()
    var counts: [String: Int] = [:]
    var startupProbeStartTime: CFAbsoluteTime?
    var startupProbeExpectedStart: Double?
    var startupProbeArmed = false
  }

  private static let state = State()
  private static let timestampFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private static func timestamp() -> String {
    timestampFormatter.string(from: Date())
  }

  /// İlk `first` satır + sonra her `every` çağrıda bir satır (`every == 0` → yalnızca ilk `first`).
  static func throttled(
    _ tag: String,
    first: Int = 40,
    every: Int = 90,
    _ message: () -> String
  ) {
    state.lock.lock()
    let n = (state.counts[tag] ?? 0) + 1
    state.counts[tag] = n
    state.lock.unlock()
    if n <= first || (every > 0 && n % every == 0) {
      NSLog("%@", "[\(timestamp())] MPVPlayer.\(tag) #\(n): \(message())")
    }
  }

  static func always(_ tag: String, _ message: String) {
    NSLog("%@", "[\(timestamp())] MPVPlayer.\(tag): \(message)")
  }

  static func armStartupProbe(expectedStartSeconds: Double?) {
    state.lock.lock()
    state.startupProbeStartTime = CFAbsoluteTimeGetCurrent()
    state.startupProbeExpectedStart = expectedStartSeconds
    state.startupProbeArmed = true
    state.lock.unlock()
  }

  static func recordFrameForStartupProbe(_ pb: CVPixelBuffer) {
    state.lock.lock()
    let armed = state.startupProbeArmed
    let start = state.startupProbeStartTime
    let expected = state.startupProbeExpectedStart
    state.lock.unlock()
    guard armed, let start else { return }
    guard isLikelyNonBlack(pb) else { return }

    let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    state.lock.lock()
    state.startupProbeArmed = false
    state.startupProbeStartTime = nil
    state.startupProbeExpectedStart = nil
    state.lock.unlock()
    always(
      "Startup.metric",
      "time_to_first_non_black_ms=\(elapsedMs) expectedStart=\(expected?.description ?? "nil")"
    )
  }


  private static func isLikelyNonBlack(_ pb: CVPixelBuffer) -> Bool {
    let lockFlags = CVPixelBufferLockFlags(rawValue: 0)
    let lr = CVPixelBufferLockBaseAddress(pb, lockFlags)
    defer { CVPixelBufferUnlockBaseAddress(pb, lockFlags) }
    guard lr == kCVReturnSuccess else { return false }
    guard let base = CVPixelBufferGetBaseAddress(pb) else { return false }
    let w = CVPixelBufferGetWidth(pb)
    let h = CVPixelBufferGetHeight(pb)
    let bpr = CVPixelBufferGetBytesPerRow(pb)
    guard w > 0, h > 0, bpr >= 4 else { return false }
    let midY = h / 2
    let midX = w / 2
    let off = midY * bpr + midX * 4
    let px = base.load(fromByteOffset: off, as: UInt32.self)
    let b = Int(px & 0xFF)
    let g = Int((px >> 8) & 0xFF)
    let r = Int((px >> 16) & 0xFF)
    return (r + g + b) > 24
  }

  /// Orta pikselin ham 4 baytı (BGRA); tam siyah/kapalı alfa ayırt etmek için.
  static func pixelBufferSummary(_ pb: CVPixelBuffer) -> String {
    let w = CVPixelBufferGetWidth(pb)
    let h = CVPixelBufferGetHeight(pb)
    let fmt = CVPixelBufferGetPixelFormatType(pb)
    let lockFlags = CVPixelBufferLockFlags(rawValue: 0)
    let lr = CVPixelBufferLockBaseAddress(pb, lockFlags)
    defer { CVPixelBufferUnlockBaseAddress(pb, lockFlags) }
    if lr != kCVReturnSuccess {
      return "w=\(w) h=\(h) fmt=\(fmt) lockFailed=\(lr)"
    }
    guard let base = CVPixelBufferGetBaseAddress(pb) else {
      return "w=\(w) h=\(h) fmt=\(fmt) base=nil"
    }
    let bpr = CVPixelBufferGetBytesPerRow(pb)
    if w < 1 || h < 1 { return "w=\(w) h=\(h) fmt=\(fmt) empty" }
    let midY = h / 2
    let midX = w / 2
    let off = midY * bpr + midX * 4
    let u32 = base.load(fromByteOffset: off, as: UInt32.self)
    let c0 = base.load(fromByteOffset: 0, as: UInt32.self)
    return
      "w=\(w) h=\(h) fmt=\(fmt) bpr=\(bpr) cornerU32=0x\(String(c0, radix: 16)) midU32=0x\(String(u32, radix: 16))"
  }
}
