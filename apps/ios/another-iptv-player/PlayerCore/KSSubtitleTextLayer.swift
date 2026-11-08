import SwiftUI
import KSPlayer

/// Bitmap (PGS / DVB) cue rendering on the video surface. The bitmap is positioned in
/// the video's own pixel space, so it is part of the picture and follows its transform.
struct KSSubtitleBitmapOverlay: View {
  let image: UIImage?
  /// Native-frame pixel position of `image` (top-left origin), from `SubtitlePart.origin`.
  let imageOrigin: CGPoint
  /// Video's native pixel size, used to scale `image`/`imageOrigin` down to the
  /// overlay's displayed point size instead of stretching the bitmap to fill it.
  let naturalSize: CGSize

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottom) {
        if let image {
          let scale = naturalSize.width > 0 ? proxy.size.width / naturalSize.width : 1
          #if os(macOS)
          let bitmap = Image(nsImage: image)
          #else
          let bitmap = Image(uiImage: image)
          #endif
          bitmap
            .resizable()
            .frame(width: image.size.width * scale, height: image.size.height * scale)
            .position(
              x: (imageOrigin.x + image.size.width / 2) * scale,
              y: (imageOrigin.y + image.size.height / 2) * scale
            )
        }
      }
      // The ZStack must fill the whole surface: that gives `.position()` the
      // full-surface coordinate space it expects.
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .allowsHitTesting(false)
  }
}

/// Text cues, drawn in a layer of their own that the player mounts next to the video
/// surface instead of inside it. Inside the surface they were scaled, panned and cropped
/// together with the picture: Fill cut the bottom line off and a pinch zoomed them away.
///
/// The owner frames this view to the visible picture and says how far the cue has to
/// stay from the bottom edge of that frame. The view observes the engine itself, and the
/// cue keeps arriving during a cast, where the cast clock drives `updateSubtitleCue`.


struct KSSubtitleTextLayer: View {
  @ObservedObject var engine: KSPlayerEngine
  /// Added below the user's own vertical offset (for example the part of the bottom
  /// safe area that reaches into the picture).
  var bottomInset: CGFloat = 0
  /// The cue's bottom edge is never closer than this to the layer's bottom edge,
  /// whatever the offset is (for example to clear a visible scrubber). It lifts the cue
  /// only by what the offset and `bottomInset` do not already cover.
  var minimumBottomClearance: CGFloat = 0

  var body: some View {
    let appearance = engine.subtitleAppearance
    ZStack {
      // A bitmap cue wins, as it always did: the surface draws that one.
      if engine.subtitleImage == nil, let text = engine.subtitleText, !text.string.isEmpty {
        KSSubtitleCueText(text: text.string, appearance: appearance)
          // Skips the outline pass (many glyph stamps) on engine ticks that leave the
          // cue and its style unchanged.
          .equatable()
          .padding(.bottom, bottomPadding(for: appearance))
          // A cue cuts in and out; it must not fade because some other animation
          // (the chrome cross-fade, the mini morph) happens to be in flight.
          .transition(.identity)
      }
    }
    // The alignment places the text block: `multilineTextAlignment` alone only aligns
    // the lines inside the block, so Left/Right never moved a real cue.
    .frame(
      maxWidth: .infinity, maxHeight: .infinity,
      alignment: KSSubtitleCueText.blockAlignment(for: appearance)
    )
    .allowsHitTesting(false)
  }

  private func bottomPadding(for appearance: SubtitleAppearanceSettings) -> CGFloat {
    let own = max(CGFloat(appearance.verticalOffset) + 12, 0) + max(bottomInset, 0)
    return max(own, minimumBottomClearance)
  }
}

/// One text cue with the user's subtitle appearance settings applied. ASS-styled
/// attributed strings are flattened to plain text — same behavior as the mpv engine's
/// `sub-ass-override=force`.
private struct KSSubtitleCueText: View, Equatable {
  let text: String
  let appearance: SubtitleAppearanceSettings

  var body: some View {
    Text(appearance.applyingWordSpacing(to: text))
      .font(styledFont)
      .italic(appearance.italic)
      .kerning(appearance.letterSpacing)
      .lineSpacing(max(appearance.lineHeight - 1, 0) * CGFloat(appearance.renderedFontPointSize))
      .multilineTextAlignment(textAlignment)
      .foregroundStyle(Color(hex6: appearance.textColorHex6))
      .subtitleOutline(appearance)
      .padding(.horizontal, CGFloat(appearance.padding) + 8)
      .padding(.vertical, 4)
      .background(backgroundFill)
      .padding(.horizontal, blockEdgeInset)
  }

  /// System font with the chosen weight. The former `SFProDisplay-*` PostScript names
  /// are not addressable on the device, so every weight resolved to one fallback face;
  /// `system(size:weight:)` is also a fixed size, where `custom(_:size:)` grew with
  /// Dynamic Type on top of the user's subtitle size.
  private var styledFont: Font {
    Font.system(size: CGFloat(appearance.renderedFontPointSize), weight: styledWeight)
  }

  private var styledWeight: Font.Weight {
    switch appearance.fontWeight {
    case .thin: return .thin
    case .normal: return .regular
    case .medium: return .medium
    case .bold: return .bold
    case .extraBold: return .heavy
    }
  }

  private var textAlignment: TextAlignment {
    switch appearance.textAlignment {
    case .left: return .leading
    case .right: return .trailing
    case .center, .justify: return .center
    }
  }

  /// Where the cue block sits inside the layer that hosts it.
  static func blockAlignment(for appearance: SubtitleAppearanceSettings) -> Alignment {
    switch appearance.textAlignment {
    case .left: return .bottomLeading
    case .right: return .bottomTrailing
    case .center, .justify: return .bottom
    }
  }

  /// Keeps a side-aligned block (and its background box) off the screen edge and the
  /// rounded display corners. Centered cues keep their previous full-width layout.
  private var blockEdgeInset: CGFloat {
    switch appearance.textAlignment {
    case .left, .right: return 12
    case .center, .justify: return 0
    }
  }

  @ViewBuilder private var backgroundFill: some View {
    if appearance.backgroundEnabled {
      RoundedRectangle(cornerRadius: 4)
        .fill(Color(hex6: appearance.backgroundColorHex6).opacity(appearance.backgroundOpacity))
    }
  }
}

/// Draws a subtitle `Text` with a hard outline: the glyphs are stamped at offsets that
/// cover a disc of `width` points, the union is filled with the outline color, and the
/// normal text is drawn on top. A blurred shadow (the previous approach) is a soft halo
/// that washes out on bright scenes. Not private, so the appearance preview can apply
/// the same renderer through `SubtitleAppearanceSettings.outlineRenderer`.
/// `nonisolated`: SwiftUI's `TextRenderer` requirements are not main-actor isolated.
@available(macOS 15.0, *)
nonisolated struct KSSubtitleOutlineRenderer: TextRenderer {
  let color: Color
  /// Outline thickness in points; 0 draws the text without an outline.
  let width: CGFloat
  private let offsets: [CGSize]

  init(color: Color, width: CGFloat) {
    self.color = color
    self.width = max(width, 0)
    offsets = Self.stampOffsets(radius: max(width, 0))
  }

  /// The outline is drawn outside the text's layout bounds; without this it is clipped.
  var displayPadding: EdgeInsets {
    let inset = width.rounded(.up)
    return EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
  }

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    if !offsets.isEmpty {
      var bounds = CGRect.null
      for line in layout {
        bounds = bounds.union(line.typographicBounds.rect)
      }
      if !bounds.isNull {
        // The stamps only build an alpha mask; filling through it gives one flat
        // outline color whatever the text color is, and overlapping stamps cannot
        // darken each other.
        var outline = context
        outline.clipToLayer { mask in
          for offset in offsets {
            var stamp = mask
            stamp.translateBy(x: offset.width, y: offset.height)
            for line in layout {
              stamp.draw(line)
            }
          }
        }
        // Glyph ink (italics, descenders) can leave the typographic bounds, so the
        // fill is generously larger than them; the mask does the real clipping.
        let slop = width + bounds.height
        outline.fill(Path(bounds.insetBy(dx: -slop, dy: -slop)), with: .color(color))
      }
    }
    for line in layout {
      context.draw(line)
    }
  }

  /// Stamp positions covering a disc of `radius`. The outer ring is dense because it
  /// forms the visible edge (a fixed eight stamps look scalloped on wide outlines);
  /// the inner rings only fill the gap between a thin stem and the outer ring. The
  /// number of stamps therefore grows with the outline width.
  private static func stampOffsets(radius: CGFloat) -> [CGSize] {
    guard radius > 0.01 else { return [] }
    let ringStep: CGFloat = 0.75
    let ringCount = max(Int((radius / ringStep).rounded(.up)), 1)
    var result: [CGSize] = []
    for ring in 1...ringCount {
      let ringRadius = radius * CGFloat(ring) / CGFloat(ringCount)
      let isOuterRing = ring == ringCount
      let arcStep: CGFloat = isOuterRing ? 0.35 : 0.75
      let count = max(isOuterRing ? 12 : 8, Int((2 * CGFloat.pi * ringRadius / arcStep).rounded(.up)))
      for index in 0..<count {
        let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(count)
        result.append(CGSize(width: cos(angle) * ringRadius, height: sin(angle) * ringRadius))
      }
    }
    return result
  }
}

extension SubtitleAppearanceSettings {
  /// Outline renderer for a subtitle `Text` drawn with these settings. The stored
  /// outline size goes through the same `renderPointScale` as the font size, so the
  /// outline keeps its proportion to the glyphs (the default 2 is a 1 pt stroke on
  /// the default 20 pt text).
  @available(macOS 15.0, *)
  var outlineRenderer: KSSubtitleOutlineRenderer {
    KSSubtitleOutlineRenderer(
      color: Color(hex6: outlineColorHex6),
      width: CGFloat(outlineSize * Self.renderPointScale)
    )
  }
}

private extension Color {
  init(hex6: UInt32) {
    self.init(
      red: Double((hex6 >> 16) & 0xFF) / 255.0,
      green: Double((hex6 >> 8) & 0xFF) / 255.0,
      blue: Double(hex6 & 0xFF) / 255.0
    )
  }
}

extension View {
  @ViewBuilder func subtitleOutline(_ settings: SubtitleAppearanceSettings) -> some View {
    if #available(macOS 15.0, *) {
      textRenderer(settings.outlineRenderer)
    } else {
      let radius = CGFloat(settings.outlineSize * SubtitleAppearanceSettings.renderPointScale)
      let color = Color(hex6: settings.outlineColorHex6)
      shadow(color: color, radius: 0, x: radius, y: 0)
        .shadow(color: color, radius: 0, x: -radius, y: 0)
        .shadow(color: color, radius: 0, x: 0, y: radius)
        .shadow(color: color, radius: 0, x: 0, y: -radius)
    }
  }
}
