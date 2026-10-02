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
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            
            ZoomableImageView(url: url, placeholderRequest: placeholderRequest) {
                dismiss()
            }
            .ignoresSafeArea()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            }
            .buttonStyle(.plain)
            .padding(.top, 40)
        }
    }
}
