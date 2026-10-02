import SwiftUI

/// A selectable pill: a guide day, a season, a filter. One look for all of them, and
/// one place for what the hand-built ones each left out: the selected trait for
/// VoiceOver, a pressed state and a touch area of full height.
///
/// `compact` is the denser size for rows whose height other layout depends on (the
/// guide's day picker).
///
/// The caller keeps what belongs to its row: the animation around the selection
/// change, `.id(...)` and scrolling the selected chip into view.
struct FilterChip: View {
    private let title: String
    private let isSelected: Bool
    private let compact: Bool
    private let action: () -> Void

    init(_ title: String, isSelected: Bool, compact: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.compact = compact
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            // The selected chip is semibold. Laying every chip out at that weight
            // and drawing the real one on top keeps its width the same in both
            // states, so selecting a chip does not shift its neighbours.
            Text(title)
                .fontWeight(.semibold)
                .hidden()
                // Only a measure: VoiceOver and UI tests must find the title once.
                .accessibilityHidden(true)
                .overlay {
                    Text(title)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                }
                .font(compact ? .caption : .subheadline)
                .lineLimit(1)
                .padding(.horizontal, compact ? 12 : 14)
                .padding(.vertical, compact ? 6 : 7)
                .background(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary),
                    in: Capsule()
                )
                .minimumHitHeight()
        }
        .buttonStyle(.dimPress)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
