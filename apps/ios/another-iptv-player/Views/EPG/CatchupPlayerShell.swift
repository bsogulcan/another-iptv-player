import SwiftUI
import Combine

/// Bridge type: the guide/detail surfaces map their EPG programme into this so
/// `CatchupPlayerShell` doesn't depend on XMLTV internals.
struct CatchupProgramme: Equatable {
    let title: String
    let description: String?
    let startUTC: Date
    let stopUTC: Date
}

/// Presents a pre-resolved Xtream timeshift stream as a finite (VOD-like) asset:
/// `isLiveStream: false` gives a seek bar (when the panel supports it), no live
/// chrome, and — via `suppressWatchHistory` — no history contamination.
struct CatchupPlayerShell: View {
    let playlist: Playlist
    let stream: DBLiveStream
    let programme: CatchupProgramme
    let url: URL

    var body: some View {
        PlayerView(
            url: url,
            title: programme.title,
            subtitle: "\(stream.name) · \(EPGTimeFormat.range(programme.startUTC, programme.stopUTC))",
            artworkURL: stream.streamIcon.flatMap { URL(string: $0) },
            isLiveStream: false,
            playlistId: playlist.id,
            streamId: String(stream.streamId),
            type: "live",
            suppressWatchHistory: true,
            // The resolver's probe sees only the playlist text. When the `.m3u8` it
            // chose does not play, the next catch-up start goes back to `.ts`.
            onPlaybackFailure: { playedSeconds in
                let failedURL = url
                let playlistId = playlist.id
                Task {
                    await CatchupURLResolver.reportPlaybackFailure(
                        of: failedURL, playedSeconds: playedSeconds, playlistId: playlistId)
                }
            }
        )
    }
}

/// Resolves a timeshift URL (off-main probe) and presents the catch-up player via
/// the shared player overlay. Reused by the guide and channel-detail surfaces.
@MainActor
final class CatchupPlaybackController: ObservableObject {
    @Published var isResolving = false
    @Published var errorMessage: String?

    /// Shared across every instance so a stale resolve from a different sheet's
    /// controller can't overlay-present after a newer catch-up request started.
    private static var requestGeneration = 0

    func play(playlist: Playlist, stream: DBLiveStream, programme: CatchupProgramme,
              overlay: PlayerOverlayController) async {
        guard !isResolving else { return }
        isResolving = true
        defer { isResolving = false }

        Self.requestGeneration += 1
        let generation = Self.requestGeneration

        let timeZone = await PanelTimeZoneResolver.resolve(playlist: playlist)
        let duration = CatchupAvailability.requestDurationMinutes(
            programmeStart: programme.startUTC, programmeStop: programme.stopUTC)
        do {
            let resolved = try await CatchupURLResolver.resolve(
                playlist: playlist, streamId: stream.streamId,
                startUTC: programme.startUTC, durationMinutes: duration,
                panelTimeZone: timeZone)
            guard generation == Self.requestGeneration else { return }
            overlay.present(playlistId: playlist.id) {
                CatchupPlayerShell(playlist: playlist, stream: stream, programme: programme, url: resolved.url)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("epg.catchup.error.unavailable")
        }
    }
}
