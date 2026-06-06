import SwiftUI

struct FullscreenImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            
            ZoomableImageView(url: url) {
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
