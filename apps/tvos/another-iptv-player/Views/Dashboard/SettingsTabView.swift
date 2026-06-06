import SwiftUI
import GRDB

struct SettingsTabView: View {
    let playlist: Playlist
    let onSwitchPlaylist: () -> Void
    @EnvironmentObject private var contentStore: PlaylistContentStore

    @State private var filterAdultContent: Bool
    @State private var isRefreshing = false
    @State private var isApplyingFilter = false
    @State private var refreshError: String?

    init(playlist: Playlist, onSwitchPlaylist: @escaping () -> Void) {
        self.playlist = playlist
        self.onSwitchPlaylist = onSwitchPlaylist
        _filterAdultContent = State(initialValue: playlist.filterAdultContent)
    }

    var body: some View {
        Form {
            Section(L("settings.playlist")) {
                HStack {
                    Text(L("settings.name"))
                    Spacer()
                    Text(playlist.name)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(L("settings.server"))
                    Spacer()
                    Text(playlist.serverURL)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Section {
                Toggle(isOn: $filterAdultContent) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("settings.filter_adult.title"))
                        Text(playlist.kind == .m3u
                             ? L("settings.filter_adult.m3u_desc")
                             : L("settings.filter_adult.xtream_desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isApplyingFilter || isRefreshing)
                .onChange(of: filterAdultContent) { _, newValue in
                    Task { await applyFilterChange(newValue: newValue) }
                }
                if isApplyingFilter {
                    HStack {
                        ProgressView()
                        Text(L("settings.refresh_content"))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L("settings.content_management.title"))
            }

            Section {
                Button {
                    Task { await refreshContent() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(L("settings.refresh_content"))
                        Spacer()
                        if isRefreshing {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRefreshing || isApplyingFilter)

                Button {
                    onSwitchPlaylist()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.stack")
                        Text(L("settings.back_to_playlists"))
                    }
                }
            }
        }
        .navigationTitle(L("dashboard.settings"))
        .alert(L("loading.error.title"),
               isPresented: Binding(
                get: { refreshError != nil },
                set: { if !$0 { refreshError = nil } }
               )
        ) {
            Button(L("common.ok")) { refreshError = nil }
        } message: {
            Text(refreshError ?? "")
        }
    }

    @MainActor
    private func refreshContent() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await contentStore.refreshFromNetwork(playlist: playlist)
        } catch {
            refreshError = error.localizedDescription
        }
    }

    @MainActor
    private func applyFilterChange(newValue: Bool) async {
        guard newValue != playlist.filterAdultContent else { return }

        isApplyingFilter = true
        defer { isApplyingFilter = false }

        var updated = playlist
        updated.filterAdultContent = newValue

        do {
            try await AppDatabase.shared.write { db in try updated.save(db) }

            switch updated.kind {
            case .xtream:
                try await contentStore.refreshFromNetwork(playlist: updated)
            case .m3u:
                try await reimportM3U(playlist: updated)
            }
        } catch {
            refreshError = error.localizedDescription
            filterAdultContent = !newValue
        }
    }

    private func reimportM3U(playlist: Playlist) async throws {
        let trimmedURL = playlist.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        let rawContent = try await M3UService().fetchRemote(urlString: trimmedURL)
        let parsed = try await M3UParser.parseAsync(rawContent)

        let visibleChannels = playlist.filterAdultContent
            ? parsed.channels.filter { ch in
                if AdultContentFilter.isAdultCategoryName(ch.name) { return false }
                if let group = ch.groupTitle, AdultContentFilter.isAdultCategoryName(group) { return false }
                return true
              }
            : parsed.channels

        try await M3UImporter.replace(
            playlist: playlist,
            channels: visibleChannels,
            epgURL: parsed.epgURL,
            clearServerURL: false
        )
    }
}
