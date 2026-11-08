import AppKit
import KSPlayer
import SwiftUI

struct MacDiagnosticControls: View {
  @Binding var showOverlay: Bool
  let url: URL
  @AppStorage private var nativeLiveCast: Bool
  private let castDefaults: UserDefaults
  private let pasteboard: NSPasteboard

  init(showOverlay: Binding<Bool>, url: URL, castDefaults: UserDefaults = .standard,
       pasteboard: NSPasteboard = .general) {
    _showOverlay = showOverlay
    self.url = url
    self.castDefaults = castDefaults
    self.pasteboard = pasteboard
    _nativeLiveCast = AppStorage(wrappedValue: false, CastNativeURL.enabledDefaultsKey, store: castDefaults)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle(L("player.show_debug_overlay"), isOn: $showOverlay)
      Toggle(L("player.airplay.native_live_cast"), isOn: $nativeLiveCast)
        .onChange(of: nativeLiveCast) { _, enabled in
          if enabled { CastNativeURL.forgetFailures(defaults: castDefaults) }
        }
      Divider()
      Text(L("player.stream_url.title")).font(.headline)
      Text(verbatim: url.absoluteString).font(.system(.caption, design: .monospaced))
        .lineLimit(4).textSelection(.enabled)
      MacDiagnosticCopyButton(title: L("player.stream_url.copy"), pasteboard: pasteboard) {
        url.absoluteString
      }
      Divider()
      MacDiagnosticCopyButton(title: L("player.debug.copy_airplay_log"), pasteboard: pasteboard) {
        AirPlayLogExport.text()
      }
    }.padding(16).frame(width: 320)
  }
}

private struct MacDiagnosticCopyButton: View {
  let title: String
  var pasteboard: NSPasteboard = .general
  let text: () -> String
  @State private var copiedAt: Date?

  var body: some View {
    Button {
      pasteboard.clearContents()
      if pasteboard.setString(text(), forType: .string) { copiedAt = Date() }
    } label: {
      Label(copiedAt == nil ? title : L("player.stream_url.copied"),
            systemImage: copiedAt == nil ? "doc.on.doc" : "checkmark")
    }.task(id: copiedAt) {
      guard copiedAt != nil else { return }
      do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
      copiedAt = nil
    }
  }
}

struct MacPlaybackDiagnostics: View {
  let engine: KSPlayerEngine
  let isNetwork: Bool
  @State private var lines: [String] = []
  @State private var logTail: [String] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      ForEach(Array(lines.enumerated()), id: \.offset) { _, line in Text(verbatim: line) }
      if !logTail.isEmpty {
        Divider()
        ForEach(Array(logTail.enumerated()), id: \.offset) { _, line in
          Text(verbatim: line).font(.caption2).lineLimit(2)
        }
      }
      MacDiagnosticCopyButton(title: L("player.debug.copy_airplay_log")) { AirPlayLogExport.text() }
        .controlSize(.small)
    }
    .font(.system(.caption, design: .monospaced)).monospacedDigit()
    .padding(10).frame(maxWidth: 300, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    .task { await sampleWhileVisible() }
  }

  private func sampleWhileVisible() async {
    var rates: [(time: TimeInterval, value: Double)] = []
    var previousRead: (time: TimeInterval, bytes: Int64)?
    while !Task.isCancelled {
      let time = ProcessInfo.processInfo.systemUptime
      let info = engine.layer?.player.dynamicInfo
      let bytes = info?.bytesRead
      let bitrate = engine.videoBitrate
      if bitrate.isFinite && bitrate > 0 { rates.append((time, bitrate)) }
      rates.removeAll { time - $0.time > 5 }
      let samples = rates.map(\.value)
      var speed = "—"
      if isNetwork, let bytes, let previousRead, bytes >= previousRead.bytes, time > previousRead.time {
        speed = rate(Double(bytes - previousRead.bytes) * 8 / (time - previousRead.time))
      }
      previousRead = bytes.map { (time, $0) }
      let resolution = engine.videoDisplayWidth > 0 && engine.videoDisplayHeight > 0
        ? "\(engine.videoDisplayWidth) × \(engine.videoDisplayHeight)" : "—"
      let fps = [engine.renderFPS, engine.streamFPS].filter { $0 > 0 && $0.isFinite }
        .map { $0.formatted(.number.locale(AppLocale.current).precision(.fractionLength(0...2))) }.joined(separator: " / ")
      let range: String
      if let low = samples.min(), let high = samples.max() {
        let average = rate(samples.reduce(0, +) / Double(samples.count))
        range = low == high ? average : "\(average) (\(rate(low)) – \(rate(high)))"
      } else {
        range = "—"
      }
      let codec = [engine.hwdecCurrent, engine.videoCodecName, engine.audioCodecName]
        .filter { !$0.isEmpty }.joined(separator: " / ")
      let buffer = max(0, engine.bufferTimelineEnd - engine.position)
      let rows = [
        "RES  \(resolution)", "FPS  \(fps.isEmpty ? "—" : fps)", "BR   \(range)",
        "DROP \(engine.droppedFrameCount)", "BUF  \(buffer.formatted(.number.locale(AppLocale.current).precision(.fractionLength(1)))) s",
        "A/V  \(engine.avSyncSeconds.formatted(.number.locale(AppLocale.current).precision(.fractionLength(3)))) s",
        "NET  \(speed)", "DEC  \(codec.isEmpty ? "—" : codec)",
        "SEEK \(engine.lastSeekMilliseconds.map { "\($0) ms" } ?? "—")"
      ]
      if lines != rows { lines = rows }
      let tail = Array(Log.recentLines(tags: AirPlayLogExport.tags).suffix(4))
      if logTail != tail { logTail = tail }
      do { try await Task.sleep(for: .seconds(1)) } catch { return }
    }
  }

  private func rate(_ bps: Double) -> String {
    let mega = bps >= 1_000_000
    let amount = (bps / (mega ? 1_000_000 : 1000)).formatted(.number.locale(AppLocale.current).precision(.fractionLength(0...2)))
    return amount + (mega ? " Mbit/s" : " kbit/s")
  }
}
