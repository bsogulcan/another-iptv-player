import SwiftUI

/// macOS pencere altı durum çubuğu — Mail / Finder pattern.
/// Sol: playlist + sync durumu. Sağ: içerik sayıları.
struct StatusBar: View {
    let playlistName: String
    let isLoading: Bool
    let liveCount: Int
    let vodCount: Int
    let seriesCount: Int

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().controlSize(.small)
                    Text("Updating \(playlistName)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(playlistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 14) {
                counter("tv", liveCount)
                counter("film", vodCount)
                counter("play.tv", seriesCount)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 26)
        .background(.bar)
    }

    private func counter(_ system: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system)
            Text(value.formatted())
        }
    }
}
