import SwiftUI

/// MPVPlayer `MaterialSeekBar` ile aynı mantık:
/// - Sürüklerken (`tapped`) oynatıcıdan gelen `position` yerine `slider` oranı kullanılır.
/// - Parmak hareketi boyunca `seek` (Dart’taki `onPointerMove` / `onPointerUp`).
/// - Arka plan + buffer (`demuxer-cache-time` / süre) + kırmızı ilerleme + yuvarlak thumb.
/// - Renkler: `seekBarColor` / `seekBarBufferColor` ≈ `0x3DFFFFFF`, `seekBarPositionColor` / thumb kırmızı.
public struct MPVPlayerMaterialSeekBar: View {
  @ObservedObject var player: MPVPlayer

  private let trackHeight: CGFloat = 2.4
  private let thumbSize: CGFloat = 12.8
  private let containerHeight: CGFloat = 36

  private static let barBackground = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 61 / 255)
  private static let progressColor = Color(red: 1, green: 0, blue: 0)

  @State private var isScrubbing = false
  @State private var scrubFraction: Double = 0

  public init(player: MPVPlayer) {
    self.player = player
  }

  public var body: some View {
    let duration = max(0, player.duration)
    let enabled = player.isReady && duration > 0

    VStack(alignment: .leading, spacing: 6) {
      GeometryReader { geo in
        let w = max(1, geo.size.width)
        let liveFrac = liveFraction(duration: duration)
        let showFrac = isScrubbing ? scrubFraction : liveFrac
        let bufFrac = bufferFraction(duration: duration)

        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
            .fill(Self.barBackground)
            .frame(width: w, height: trackHeight)

          RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
            .fill(Self.barBackground)
            .frame(width: w * bufFrac, height: trackHeight)

          RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
            .fill(Self.progressColor)
            .frame(width: w * showFrac, height: trackHeight)

          Circle()
            .fill(Self.progressColor)
            .frame(width: thumbSize, height: thumbSize)
            .offset(x: w * showFrac - thumbSize / 2)
        }
        .frame(width: w, height: containerHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              guard enabled else { return }
              let f = min(1, max(0, value.location.x / w))
              if !isScrubbing {
                isScrubbing = true
                scrubFraction = f
              } else {
                scrubFraction = f
              }
              player.seek(to: duration * f)
            }
            .onEnded { _ in
              guard enabled else { return }
              player.seek(to: duration * scrubFraction)
              isScrubbing = false
            }
        )
      }
      .frame(height: containerHeight)
      .opacity(enabled ? 1 : 0.35)
      .allowsHitTesting(enabled)

      HStack {
        Text(Self.formatClock(displayPosition(duration: duration)))
          .font(.caption.monospacedDigit())
        Spacer(minLength: 8)
        Text(Self.formatClock(duration))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Oynatma konumu")
      .accessibilityValue(
        "\(Self.formatClock(displayPosition(duration: duration))) / \(Self.formatClock(duration))"
      )
    }
  }

  private func liveFraction(duration: TimeInterval) -> Double {
    guard duration > 0 else { return 0 }
    return min(1, max(0, player.position / duration))
  }

  private func bufferFraction(duration: TimeInterval) -> Double {
    guard duration > 0 else { return 0 }
    let end = player.bufferTimelineEnd
    guard end > 0 else { return 0 }
    return min(1, max(0, end / duration))
  }

  private func displayPosition(duration: TimeInterval) -> TimeInterval {
    guard duration > 0 else { return 0 }
    if isScrubbing { return duration * scrubFraction }
    return player.position
  }

  private static func formatClock(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, !seconds.isNaN, seconds >= 0 else { return "0:00" }
    let s = Int(seconds.rounded(.down))
    let h = s / 3600
    let m = (s % 3600) / 60
    let r = s % 60
    if h > 0 {
      return String(format: "%d:%02d:%02d", h, m, r)
    }
    return String(format: "%d:%02d", m, r)
  }
}
