import SwiftUI

/// The zoom from a poster to its detail screen (movies and series, shelves and grids).
enum BrowseTransitions {
    /// One switch for the whole app. With `false` both modifiers below return the
    /// view unchanged and the detail screens push with the standard slide.
    static let usesZoom = true
}

extension View {
    /// Marks the poster a detail screen zooms out of. `id` and `namespace` must be
    /// the ones the pushed screen passes to `posterZoomDestination(id:in:)`.
    ///
    /// Put it on the artwork, inside the link's label, so the screen grows out of
    /// the image and not out of the image plus its title.
    @ViewBuilder
    func posterZoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if BrowseTransitions.usesZoom {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Makes a pushed detail screen zoom out of the poster marked with
    /// `posterZoomSource(id:in:)`. Apply it to the destination's root view.
    @ViewBuilder
    func posterZoomDestination<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        modifier(PosterZoomDestination(id: id, namespace: namespace))
    }
}

private struct PosterZoomDestination<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if BrowseTransitions.usesZoom && !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
