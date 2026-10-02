import SwiftUI
import UIKit

/// Pointer feedback for cards on iPad.
enum CardHover {
    /// Only iPad has a pointer. The effect is switched off elsewhere instead of
    /// being left to do nothing, so an iPhone does not carry a hover effect for
    /// every card of a list.
    static let isSupported = UIDevice.current.userInterfaceIdiom == .pad
}

extension View {
    /// Highlights the artwork of a card under the pointer, in the artwork's own
    /// rounded shape. Apply it to the artwork (poster, logo tile), not to the whole
    /// card: the highlight then follows the image and leaves the title alone.
    /// No effect on iPhone.
    func cardHover(cornerRadius: CGFloat) -> some View {
        self
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .hoverEffect(.highlight, isEnabled: CardHover.isSupported)
    }
}
