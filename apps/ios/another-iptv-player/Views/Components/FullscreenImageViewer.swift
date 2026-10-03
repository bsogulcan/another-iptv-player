import SwiftUI
import Nuke

struct FullscreenImageViewer: View {
    let url: URL
    /// The request under which the tapped thumbnail is on screen (build it with
    /// `CachedImage.request`, with the arguments of that thumbnail). The viewer then opens
    /// on the thumbnail instead of a spinner on black.
    var placeholderRequest: ImageRequest? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ZoomableImageView(url: url, placeholderRequest: placeholderRequest) {
                    dismiss()
                }
                .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    closeButton
                        .accessibilityLabel(L("common.close"))
                        .accessibilityIdentifier("artwork.close")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var closeButton: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close) { dismiss() }
        } else {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
        }
    }
}
