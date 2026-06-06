import SwiftUI

/// `+` basıldığında açılır; kullanıcı Xtream Code / M3U seçimi yapar.
struct PlaylistTypeSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    let onSelectXtream: () -> Void
    let onSelectM3U: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(L("playlist_type.section"))) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onSelectXtream()
                        }
                    } label: {
                        row(
                            icon: "server.rack",
                            title: L("playlist_type.xtream.title"),
                            subtitle: L("playlist_type.xtream.subtitle")
                        )
                    }

                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onSelectM3U()
                        }
                    } label: {
                        row(
                            icon: "list.bullet.rectangle.portrait",
                            title: L("playlist_type.m3u.title"),
                            subtitle: L("playlist_type.m3u.subtitle")
                        )
                    }
                }
            }
            .foregroundColor(.primary)
            .navigationTitle(L("playlist_type.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
