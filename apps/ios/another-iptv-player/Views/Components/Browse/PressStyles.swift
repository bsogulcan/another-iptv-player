import SwiftUI

// One pressed look for everything in the browse screens that is a button with a
// custom label. Cards (posters, channel tiles, history cards) shrink a little and dim;
// rows, chips, shelf headers and text buttons only dim.
//
// Both are `ButtonStyle`s driven by `configuration.isPressed` on purpose. The
// enclosing scroll view decides when a touch becomes a press: a flick across a shelf
// never raises `isPressed`, and a pan or a context-menu long press that starts after
// it was raised cancels it. A style built on its own `DragGesture` or
// `onLongPressGesture(pressing:)` would compete with the shelf's pan instead.
//
// Attach `.contextMenu` to the button or link, outside its label: when the long
// press is recognised the system cancels the touch, the card settles back and the
// system lift takes over. The scale is kept small so the two do not read as a
// double bounce.

/// Pressed state for cards: a slight scale-down and dim. Under Reduce Motion the card
/// only dims.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressFeedback(configuration: configuration, pressedScale: 0.97, pressedOpacity: 0.85)
    }
}

/// Pressed state for rows, chips, shelf headers and text buttons: dim only.
struct DimPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressFeedback(configuration: configuration, pressedScale: 1, pressedOpacity: 0.55)
    }
}

extension ButtonStyle where Self == CardPressStyle {
    static var cardPress: CardPressStyle { CardPressStyle() }
}

extension ButtonStyle where Self == DimPressStyle {
    static var dimPress: DimPressStyle { DimPressStyle() }
}

/// Timing shared by both styles.
private enum PressTiming {
    /// Shortest time the pressed look stays up. Inside a scroll view a quick tap
    /// raises `isPressed` for about one frame, too short to be seen, so the tap
    /// seemed to go unanswered until the next screen appeared. Zero switches the
    /// hold off.
    static let minimumHold: Duration = .milliseconds(120)

    static let down: Animation = .easeOut(duration: 0.1)
    static let up: Animation = .spring(response: 0.28, dampingFraction: 0.7)
}

/// The label of a styled button with its pressed look. A view of its own because a
/// `ButtonStyle` cannot read the environment or hold state; this one needs Reduce
/// Motion and the hold described at `PressTiming.minimumHold`.
private struct PressFeedback: View {
    let configuration: ButtonStyleConfiguration
    let pressedScale: CGFloat
    let pressedOpacity: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True from the moment a press begins until the minimum hold has passed,
    /// whether or not the finger is still down.
    @State private var isHeld = false
    @State private var holdTimer: Task<Void, Never>?

    var body: some View {
        // `isPressed` is read directly as well, so the look starts in the frame the
        // press is reported and not one update later.
        let pressed = configuration.isPressed || isHeld
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? pressedScale : 1)
            .opacity(pressed ? pressedOpacity : 1)
            .animation(pressed ? PressTiming.down : PressTiming.up, value: pressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                guard isPressed, PressTiming.minimumHold > .zero else { return }
                isHeld = true
                holdTimer?.cancel()
                holdTimer = Task {
                    try? await Task.sleep(for: PressTiming.minimumHold)
                    guard !Task.isCancelled else { return }
                    isHeld = false
                }
            }
    }
}

extension View {
    /// Makes a control at least `minHeight` tall for touches without changing its
    /// layout: the extra area hangs over the view's edges, centred. For small text
    /// controls (shelf headers, chips, inline buttons) in rows whose spacing must
    /// stay as it is. Apply it to the label of a button, inside the button, so the
    /// area belongs to that button.
    func minimumHitHeight(_ minHeight: CGFloat = 44) -> some View {
        background {
            Color.clear
                .frame(minHeight: minHeight)
                .contentShape(Rectangle())
        }
    }
}
