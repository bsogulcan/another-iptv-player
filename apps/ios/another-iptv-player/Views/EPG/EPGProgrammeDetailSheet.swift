import SwiftUI

/// Programme detail popover: title, time, description, and context-appropriate
/// play actions (play the live channel, watch-from-start, or catch-up playback).
/// Self-contained — owns the live/catch-up presentation so both the guide and the
/// channel-detail list can present it with just the programme + channel data.
struct EPGProgrammeDetailSheet: View {
    let playlist: Playlist
    let programme: EPGProgramme
    let channelName: String
    let channelIcon: URL?
    /// Xtream live stream for this channel — enables live play + catch-up. nil for M3U.
    let liveStream: DBLiveStream?
    /// Starts the channel when there is no Xtream stream to start here: the
    /// presenter's own way of playing an M3U channel. Catch-up stays Xtream-only.
    var onPlayChannel: (() -> Void)? = nil

    @Environment(\.playerOverlayController) private var playerOverlay
    @StateObject private var catchup = CatchupPlaybackController()
    @Environment(\.dismiss) private var dismiss
    /// Not read: the store swaps it once a minute, which runs the body again so
    /// the live badge, the progress and the offered actions follow the clock.
    @Environment(\.epgSnapshot) private var epgSnapshot

    private var now: Date { Date() }
    private var isCurrent: Bool { programme.isCurrent(at: now) }

    private var catchupPlayable: Bool {
        guard let s = liveStream, s.tvArchive == 1 else { return false }
        if isCurrent {
            return CatchupAvailability.isWatchFromStart(programmeStart: programme.start, programmeStop: programme.stop, now: now)
        }
        return CatchupAvailability.isPlayable(tvArchive: s.tvArchive, tvArchiveDurationDays: s.tvArchiveDuration,
                                              programmeStart: programme.start, now: now)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        CachedImage(url: channelIcon, width: 44, height: 44, cornerRadius: 8, iconName: "tv")
                        Text(channelName).font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(programme.title).font(.title3.bold())
                        HStack(spacing: 8) {
                            Text(timeLine).font(.subheadline).foregroundColor(.secondary)
                            if isCurrent {
                                Text(L("epg.detail.live_badge"))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                            }
                        }
                        if isCurrent, let fraction = programme.progress(at: now) {
                            ProgressView(value: fraction).tint(.accentColor)
                        }
                    }

                    // The actions come before the description: at the medium detent a
                    // long synopsis would push them below the fold.
                    if canPlayChannel || catchupPlayable {
                        playButtons
                    }

                    if let error = catchup.errorMessage {
                        Text(error).font(.footnote).foregroundColor(.red)
                    }

                    if let desc = programme.desc, !desc.isEmpty {
                        Text(desc).font(.body).foregroundColor(.primary.opacity(0.9))
                    }
                }
                .padding()
            }
            .navigationTitle(L("epg.programme_detail.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
                }
            }
        }
    }

    private var canPlayChannel: Bool { liveStream != nil || onPlayChannel != nil }

    @ViewBuilder
    private var playButtons: some View {
        VStack(spacing: 10) {
            if canPlayChannel {
                Button {
                    dismiss()
                    if liveStream != nil {
                        playLiveChannel()
                    } else {
                        onPlayChannel?()
                    }
                } label: {
                    Label(L("epg.detail.play_channel"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if catchupPlayable, let stream = liveStream {
                Button {
                    let programmeBridge = CatchupProgramme(title: programme.title, description: programme.desc,
                                                           startUTC: programme.start, stopUTC: programme.stop)
                    guard let overlay = playerOverlay.injected else { return }
                    Task {
                        await catchup.play(playlist: playlist, stream: stream, programme: programmeBridge, overlay: overlay)
                        // Only close once playback actually resolved; keep the sheet open to show the error otherwise.
                        if catchup.errorMessage == nil {
                            dismiss()
                        }
                    }
                } label: {
                    if catchup.isResolving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(isCurrent ? L("epg.detail.watch_from_start") : L("epg.detail.play_catchup"),
                              systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(catchup.isResolving)
            }
        }
    }

    private var timeLine: String {
        "\(EPGTimeFormat.range(programme.start, programme.stop)) · \(EPGTimeFormat.duration(programme.duration))"
    }

    private func playLiveChannel() {
        guard let stream = liveStream else { return }
        // The live catalog as the Live tab lists it, so prev/next channel and the
        // side panel stay enabled.
        let live = EPGGuidePlayback.xtreamLiveQueue(playlistId: playlist.id, including: stream)
        playerOverlay.injected?.present(playlistId: playlist.id) {
            LivePlayerShell(playlist: playlist, queue: live.queue, sections: live.sections,
                            initialStream: stream, initialHistory: nil, subtitle: channelName)
        }
    }
}
