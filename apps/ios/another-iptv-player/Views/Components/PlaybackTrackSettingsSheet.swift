import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PlaybackTrackSettingsSheet: View {
    @ObservedObject var player: VideoPlayerController
    @Binding var showDebugOverlay: Bool
    let streamURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var didCopyURL = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var showSubtitleImporter = false
    @State private var showSubtitleImportError = false

    private static let subtitleContentTypes: [UTType] =
        ["srt", "ass", "ssa", "vtt", "sub", "smi"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        NavigationStack {
            List {
                trackSection(
                    title: L("player.tracks.video"),
                    items: player.videoTracks,
                    currentId: player.currentVideoTrackId,
                    emptyLabel: L("player.tracks.empty.video"),
                    select: { player.selectVideoTrack(id: $0) }
                )
                trackSection(
                    title: L("player.tracks.audio"),
                    items: player.audioTracks,
                    currentId: player.currentAudioTrackId,
                    emptyLabel: L("player.tracks.empty.audio"),
                    select: { player.selectAudioTrack(id: $0) }
                )
                trackSection(
                    title: L("player.tracks.subtitle"),
                    items: player.subtitleTracks,
                    currentId: player.currentSubtitleTrackId,
                    emptyLabel: L("player.tracks.empty.subtitle"),
                    select: { player.selectSubtitleTrack(id: $0) }
                )
                if !player.isLiveStream {
                    importedSubtitlesSection
                }
                Section(L("player.dev_section")) {
                    Toggle(L("player.show_debug_overlay"), isOn: $showDebugOverlay)
                }
                Section(L("player.stream_url.title")) {
                    Button(action: copyStreamURL) {
                        HStack(alignment: .top, spacing: 10) {
                            Text(streamURL.absoluteString)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Image(systemName: didCopyURL ? "checkmark" : "doc.on.doc")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(didCopyURL ? Color.accentColor : .secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(
                        didCopyURL ? L("player.stream_url.copied") : L("player.stream_url.copy")
                    )
                }
            }
            .navigationTitle(L("player.tracks.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
                }
            }
        }
        .onAppear { player.updateTracks() }
        .onDisappear { copyResetTask?.cancel() }
        .fileImporter(
            isPresented: $showSubtitleImporter,
            allowedContentTypes: Self.subtitleContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let picked = urls.first else { return }
            do {
                try player.importSubtitleFile(at: picked)
            } catch {
                showSubtitleImportError = true
            }
        }
        .alert(L("player.subtitle_import.failed"), isPresented: $showSubtitleImportError) {
            Button(L("common.close"), role: .cancel) {}
        }
    }

    /// Imported files are stored for this content and loaded automatically on future playbacks.
    private var importedSubtitlesSection: some View {
        Section {
            ForEach(player.importedSubtitleFiles, id: \.self) { file in
                Label(file.lastPathComponent, systemImage: "doc.text")
                    .foregroundStyle(.primary)
            }
            .onDelete { offsets in
                for index in offsets {
                    player.deleteImportedSubtitle(player.importedSubtitleFiles[index])
                }
            }
            Button {
                showSubtitleImporter = true
            } label: {
                Label(L("player.subtitle_import.button"), systemImage: "plus")
            }
        } header: {
            Text(L("player.subtitle_import.section"))
        } footer: {
            Text(L("player.subtitle_import.footer"))
        }
    }

    private func copyStreamURL() {
        UIPasteboard.general.string = streamURL.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        didCopyURL = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { didCopyURL = false }
        }
    }

    @ViewBuilder
    private func trackSection(
        title: String,
        items: [TrackMenuOption],
        currentId: Int,
        emptyLabel: String,
        select: @escaping (Int) -> Void
    ) -> some View {
        Section(title) {
            if items.isEmpty {
                Text(emptyLabel)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Button {
                        select(item.id)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                if let detail = item.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer(minLength: 8)
                            if item.id == currentId {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }
}
