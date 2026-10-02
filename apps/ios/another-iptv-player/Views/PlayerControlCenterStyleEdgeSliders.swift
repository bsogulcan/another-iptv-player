import Combine
import QuartzCore
import SwiftUI
import UIKit

/// iOS Kontrol Merkezi’ndeki dikey kapsül kaydırıcı görünümü: sol parlaklık, sağ sistem sesi.
///
/// Yerleşim: sol/sağ kenarlarda dikey ortada. `safeAreaInsets` ile çentik alanından uzak tutulur.
/// Compact horizontal size class'ta (iPhone) slider daraltılıp (52pt) portrait'te centerTransport
/// ile yatayda çakışması önlenir; regular size class'ta (iPad) normal genişlik.
struct PlayerControlCenterStyleEdgeSliders: View {
  /// Both models are observed here and nowhere in the player body: a brightness or
  /// volume change re-evaluates the two capsules only.
  @ObservedObject var brightness: ScreenBrightnessModel
  @ObservedObject var systemVolume: SystemVolumeBridge
  var safeAreaInsets: EdgeInsets
  var isCompactWidth: Bool
  var onInteraction: () -> Void

  private var trackWidth: CGFloat { isCompactWidth ? 52 : 64 }
  private var trackHeight: CGFloat { isCompactWidth ? 160 : 180 }

  var body: some View {
    ZStack {
      PlayerCCVerticalSlider(
        value: Binding(
          get: { Double(brightness.brightness) },
          set: { brightness.setBrightness(CGFloat($0)) }
        ),
        // Publishes on every frame of a drag, which is cheap now: this view is the
        // model's only observer.
        onLiveChange: { brightness.setBrightness(CGFloat($0)) },
        symbolName: { _ in "sun.max.fill" },
        accessibilityLabel: L("player.brightness"),
        accessibilityValueFormat: { "\(Int(round($0 * 100)))%" },
        trackWidth: trackWidth,
        trackHeight: trackHeight,
        onInteraction: onInteraction
      )
      .padding(.leading, 16 + safeAreaInsets.leading)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

      PlayerCCVerticalSlider(
        value: Binding(
          get: { Double(systemVolume.outputVolume) },
          set: { systemVolume.setOutputVolume(Float($0)) }
        ),
        // Changes the system volume without publishing; the bridge publishes when the
        // drag ends, so dragging does not re-evaluate the player body per touch-move.
        onLiveChange: { systemVolume.previewOutputVolume(Float($0)) },
        symbolName: { Self.volumeSymbolName(for: $0) },
        accessibilityLabel: L("player.volume"),
        accessibilityValueFormat: { "\(Int(round($0 * 100)))%" },
        trackWidth: trackWidth,
        trackHeight: trackHeight,
        onInteraction: onInteraction
      )
      .padding(.trailing, 16 + safeAreaInsets.trailing)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
  }

  /// Takes the value the capsule is drawing (finger-driven during a drag), not the
  /// published one, so the glyph keeps up with the fill.
  private static func volumeSymbolName(for volume: Double) -> String {
    let t = min(max(volume, 0), 1)
    if t < 0.001 { return "speaker.slash.fill" }
    if t < 0.34 { return "speaker.wave.1.fill" }
    if t < 0.67 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
  }
}

// MARK: - Screen brightness

/// System screen brightness for the in-player capsule. Owned by `VideoPlayerController`
/// as a plain `let` and observed only by the edge sliders: brightness used to be a
/// published value of the controller itself, so every step of a drag (and every change
/// made in Control Center) re-evaluated the whole player body.
///
/// Main-thread state.
final class ScreenBrightnessModel: ObservableObject {
  /// 0...1. Follows changes made outside the app through `brightnessDidChange`.
  @Published private(set) var brightness: CGFloat

  /// System brightness before the app's first in-player adjustment; restored on teardown
  /// so leaving the player never strands the whole device at the in-video level.
  private var brightnessToRestore: CGFloat?
  /// The level the app last wrote while its override is active. The change
  /// notification carries no author, so this is how an echo of the app's own write is
  /// told from a change made elsewhere (Control Center, Settings, the system).
  private var lastAppWrittenBrightness: CGFloat?
  private var brightnessObservation: AnyCancellable?

  init() {
    brightness = UIScreen.main.brightness
    brightnessObservation = NotificationCenter.default
      .publisher(for: UIScreen.brightnessDidChangeNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self else { return }
        // Guarded: the notification also echoes the app's own writes, and
        // `@Published` announces a change even for an equal value.
        let current = UIScreen.main.brightness
        // A level the app did not write is the user's (or the system's) choice: the
        // override is over, and nothing puts the old level back on top of it later.
        if self.brightnessToRestore != nil,
           ScreenBrightnessOverridePolicy.isExternalChange(
             current: current, lastAppWritten: self.lastAppWrittenBrightness
           ) {
          self.brightnessToRestore = nil
          self.lastAppWrittenBrightness = nil
        }
        if self.brightness != current { self.brightness = current }
      }
  }

  /// Sets the screen brightness and publishes it.
  func setBrightness(_ value: CGFloat) {
    let clamped = min(max(value, 0), 1)
    if brightnessToRestore == nil {
      brightnessToRestore = UIScreen.main.brightness
    }
    // Before the write: its echo is compared against this.
    lastAppWrittenBrightness = clamped
    UIScreen.main.brightness = clamped
    if brightness != clamped { brightness = clamped }
  }

  /// Puts back the brightness the device had before the first in-player adjustment.
  /// Called when the player is torn down or minimized; a no-op if nothing was adjusted,
  /// or if the level was changed outside the app since.
  func restoreBrightnessIfAdjusted() {
    guard let restore = brightnessToRestore else { return }
    brightnessToRestore = nil
    lastAppWrittenBrightness = nil
    UIScreen.main.brightness = restore
    if brightness != restore { brightness = restore }
  }
}

/// Tells an echo of the app's own brightness write from a change made outside the app.
/// Kept free of `UIScreen` so it can be unit-tested.
nonisolated enum ScreenBrightnessOverridePolicy {
  /// The system reports the level it applied, which can differ from the written one by
  /// rounding; anything within this distance is the app's own write coming back.
  static let echoTolerance: CGFloat = 0.01

  /// True when `current` is not the level the app last wrote. False while the app has
  /// written nothing (there is no override to drop then).
  static func isExternalChange(current: CGFloat, lastAppWritten: CGFloat?) -> Bool {
    guard let lastAppWritten else { return false }
    return abs(current - lastAppWritten) > echoTolerance
  }
}

// MARK: - Vertical capsule

/// iOS Kontrol Merkezi stili dikey slider: geniş kapsül, içinde edge-to-edge düz beyaz fill,
/// SF Symbol capsule'ün **içinde** alt ortada; ikon rengi fill seviyesine göre tersine döner
/// (fill üzerinde koyu, material üzerinde beyaz) — Control Center'daki davranışla eşleşir.
private struct PlayerCCVerticalSlider: View {
  /// Committed value: read while no drag is in flight, written when a drag ends and by
  /// the accessibility steps.
  @Binding var value: Double
  /// Applies a drag value to the system while the finger is still down, at most once
  /// per display frame.
  var onLiveChange: (Double) -> Void
  /// Glyph for the value being drawn.
  var symbolName: (Double) -> String
  var accessibilityLabel: String
  var accessibilityValueFormat: (Double) -> String
  var trackWidth: CGFloat = 64
  var trackHeight: CGFloat = 180
  var onInteraction: () -> Void

  @State private var dragStartValue: Double? = nil
  /// Finger-driven value, non-nil only during a drag. The capsule draws this instead of
  /// `value`, so it tracks the finger without waiting for the published value to make
  /// the round trip through the bridge / controller and the parent body.
  @State private var liveValue: Double? = nil
  /// Resets on a cancelled gesture too (`onEnded` does not run then), so a cancelled
  /// drag cannot leave the capsule stuck on `liveValue`.
  @GestureState private var isDragging = false
  @StateObject private var liveCommit = PlayerCCSliderFrameCommit()

  private var cornerRadius: CGFloat { min(trackWidth, trackHeight) * 0.4 }

  private var displayValue: Double { liveValue ?? value }

  private var fillHeight: CGFloat {
    let clamped = min(max(displayValue, 0), 1)
    return CGFloat(clamped) * trackHeight
  }

  /// Ends a drag (finished or cancelled): hands the last finger value to the binding
  /// and gives the display back to the committed value.
  private func finishDrag() {
    liveCommit.cancel()
    dragStartValue = nil
    guard let last = liveValue else { return }
    liveValue = nil
    value = last
  }

  /// İkon capsule'ün altında ~30pt (18 padding + 12 yarı-sembol) civarında oturuyor.
  /// Fill bu eşiği geçince ikon beyaz üzerinde kalır → koyu tona geçir.
  private var symbolIsOverFill: Bool {
    fillHeight >= 36
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      // Material arka plan — tüm rounded rect'i kaplar.
      Rectangle()
        .fill(.ultraThinMaterial)

      // Fill — düz beyaz, edge-to-edge, `clipShape` ile rounded corner'lara uyumlu.
      Rectangle()
        .fill(Color.white.opacity(0.95))
        .frame(height: fillHeight)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.88), value: displayValue)

      // SF Symbol — capsule'ün içinde, alt ortada.
      Image(systemName: symbolName(displayValue))
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(symbolIsOverFill ? Color.black.opacity(0.82) : Color.white)
        .shadow(
          color: symbolIsOverFill ? .clear : .black.opacity(0.35),
          radius: 2,
          y: 0.5
        )
        .padding(.bottom, 18)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.12), value: symbolIsOverFill)

      // Drag alanı — tüm capsule yüzeyi.
      Color.clear
        .contentShape(Rectangle())
        .gesture(
          // Tap ile anlık sıçrama yerine yalnızca gerçek sürükleme ile değer değiştir.
          // Sürükleme başlangıcındaki değerden itibaren göreceli hareketle güncelle.
          DragGesture(minimumDistance: 8)
            .updating($isDragging) { _, dragging, _ in
              dragging = true
            }
            .onChanged { g in
              onInteraction()
              let start = dragStartValue ?? value
              if dragStartValue == nil {
                dragStartValue = start
              }
              let delta = Double(-CGFloat(g.translation.height) / trackHeight)
              let next = min(max(start + delta, 0), 1)
              guard liveValue != next else { return }
              liveValue = next
              liveCommit.submit(next, apply: onLiveChange)
            }
        )
        .onChange(of: isDragging) { _, dragging in
          if !dragging { finishDrag() }
        }
    }
    .frame(width: trackWidth, height: trackHeight)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
    )
    .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(accessibilityValueFormat(displayValue))
    .accessibilityAdjustableAction { direction in
      onInteraction()
      let step = 0.05
      switch direction {
      case .increment:
        value = min(1, value + step)
      case .decrement:
        value = max(0, value - step)
      @unknown default:
        break
      }
    }
  }
}

// MARK: - Per-frame commit

/// Hands a drag's newest value to the system at most once per display frame. Touch
/// moves can arrive faster than the display refreshes, and neither the screen nor the
/// volume needs more than one write per frame.
///
/// The display link retains its target, so it stops itself on the first frame with
/// nothing pending: a slider that goes away mid-drag cannot leave it running.
private final class PlayerCCSliderFrameCommit: NSObject, ObservableObject {
  private var pending: (value: Double, apply: (Double) -> Void)?
  private var displayLink: CADisplayLink?

  func submit(_ value: Double, apply: @escaping (Double) -> Void) {
    pending = (value, apply)
    guard displayLink == nil else { return }
    let link = CADisplayLink(target: self, selector: #selector(tick))
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  /// Drops the pending value; the caller commits the final one itself.
  func cancel() {
    pending = nil
    stop()
  }

  @objc private func tick() {
    guard let next = pending else {
      stop()
      return
    }
    pending = nil
    next.apply(next.value)
  }

  private func stop() {
    displayLink?.invalidate()
    displayLink = nil
  }
}
