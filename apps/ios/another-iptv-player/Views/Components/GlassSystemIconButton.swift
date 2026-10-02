import SwiftUI

/// The single material recipe of the player chrome: one blur, one hairline stroke,
/// one drop shadow. The round buttons, the top-chrome capsule and the HUD pills each
/// carried a hand-rolled variant with slightly different strokes and shadows.
struct PlayerChromeMaterial<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}

extension View {
    /// Puts the view on the player chrome material, clipped to `shape`.
    func playerChromeMaterial<S: InsettableShape>(in shape: S) -> some View {
        modifier(PlayerChromeMaterial(shape: shape))
    }
}

struct GlassSystemIconButton: View {
    var systemName: String
    var pointSize: CGFloat
    var weight: Font.Weight = .semibold
    var buttonSize: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: pointSize, weight: weight))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 0.5)
                .frame(width: buttonSize, height: buttonSize)
                .playerChromeMaterial(in: Circle())
                // The glyph alone is a small target; the whole disc takes the tap.
                .contentShape(Circle())
                // Same disc for the pointer: without it the highlight takes the
                // label's rectangular bounds.
                .contentShape(.hoverEffect, Circle())
        }
        .buttonStyle(.plain)
        // Pointer (trackpad, mouse) feedback; `.plain` has none of its own. Touch is
        // unaffected.
        .hoverEffect(.highlight)
    }
}
