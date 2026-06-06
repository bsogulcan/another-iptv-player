import SwiftUI

/// iOS Kontrol Merkezi’ndeki dikey kapsül kaydırıcı görünümü: sol parlaklık, sağ sistem sesi.
///
/// Yerleşim: sol/sağ kenarlarda dikey ortada. `safeAreaInsets` ile çentik alanından uzak tutulur.
/// Compact horizontal size class'ta (iPhone) slider daraltılıp (52pt) portrait'te centerTransport
/// ile yatayda çakışması önlenir; regular size class'ta (iPad) normal genişlik.
struct PlayerControlCenterStyleEdgeSliders: View {
  @ObservedObject var player: VideoPlayerController
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
          get: { Double(player.screenBrightness) },
          set: { player.setScreenBrightness(CGFloat($0)) }
        ),
        symbolName: "sun.max.fill",
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
        symbolName: volumeSymbolName,
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

  private var volumeSymbolName: String {
    let t = min(max(Double(systemVolume.outputVolume), 0), 1)
    if t < 0.001 { return "speaker.slash.fill" }
    if t < 0.34 { return "speaker.wave.1.fill" }
    if t < 0.67 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
  }
}

// MARK: - Vertical capsule

/// iOS Kontrol Merkezi stili dikey slider: geniş kapsül, içinde edge-to-edge düz beyaz fill,
/// SF Symbol capsule'ün **içinde** alt ortada; ikon rengi fill seviyesine göre tersine döner
/// (fill üzerinde koyu, material üzerinde beyaz) — Control Center'daki davranışla eşleşir.
private struct PlayerCCVerticalSlider: View {
  @Binding var value: Double
  var symbolName: String
  var accessibilityLabel: String
  var accessibilityValueFormat: (Double) -> String
  var trackWidth: CGFloat = 64
  var trackHeight: CGFloat = 180
  var onInteraction: () -> Void

  @State private var dragStartValue: Double? = nil

  private var cornerRadius: CGFloat { min(trackWidth, trackHeight) * 0.4 }

  private var fillHeight: CGFloat {
    let clamped = min(max(value, 0), 1)
    return CGFloat(clamped) * trackHeight
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
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.88), value: value)

      // SF Symbol — capsule'ün içinde, alt ortada.
      Image(systemName: symbolName)
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
            .onChanged { g in
              onInteraction()
              if dragStartValue == nil {
                dragStartValue = value
              }
              let delta = Double(-CGFloat(g.translation.height) / trackHeight)
              value = min(max((dragStartValue ?? value) + delta, 0), 1)
            }
            .onEnded { _ in
              dragStartValue = nil
            }
        )
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
    .accessibilityValue(accessibilityValueFormat(value))
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
