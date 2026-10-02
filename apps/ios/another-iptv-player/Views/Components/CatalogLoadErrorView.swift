import SwiftUI

/// The state a catalog tab (Live, Movies, Series, M3U) shows instead of an empty page
/// when its catalog could not be loaded: what went wrong and a Try Again button.
///
/// The layout is the kit's `CatalogEmptyView`; the button sits under it so the tab
/// always has a way out without a trip to Settings.
struct CatalogLoadErrorView: View {
    let message: String
    let onRetry: () -> Void

    init(message: String, onRetry: @escaping () -> Void) {
        self.message = message
        self.onRetry = onRetry
    }

    /// For a caller that still holds the error: the text comes from `NetworkErrorText`.
    init(error: Error, onRetry: @escaping () -> Void) {
        self.init(message: NetworkErrorText.describe(error), onRetry: onRetry)
    }

    var body: some View {
        VStack(spacing: 0) {
            CatalogEmptyView(.message(
                title: L("catalog.load_failed.title"),
                systemImage: "wifi.exclamationmark",
                description: message
            ))
            .fixedSize(horizontal: false, vertical: true)

            Button(action: onRetry) {
                Label(L("common.try_again"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
