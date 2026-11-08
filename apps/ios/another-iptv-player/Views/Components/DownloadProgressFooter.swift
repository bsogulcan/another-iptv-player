import SwiftUI

/// Keep the last live value while the database observation removes a finished row.
/// The manager can remove its progress entry one frame before that observation.
struct DownloadProgressFooter: View {
    let progress: DownloadProgress?
    let stored: DownloadProgress
    @State private var lastProgress: DownloadProgress?

    var body: some View {
        let shown = progress ?? lastProgress ?? stored
        let fraction = shown.fraction
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .animation(progress == nil ? nil : .linear(duration: 0.4), value: fraction)
            HStack {
                Text(DetailFormatting.percent(fraction))
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
                if shown.totalBytes > 0 {
                    Text(DownloadFormatting.byteCount(shown.totalBytes))
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .onChange(of: progress, initial: true) { _, value in
            if let value { lastProgress = value }
        }
    }
}
