import AppKit
import Combine
import MediaPlayer

/// macOS Now Playing Center köprüsü.
///
/// macOS'ta MPNowPlayingInfoCenter aynı iOS API'sini sunar; MPRemoteCommandCenter
/// medya tuşlarını (F8/F9/F10, headset middle-button) yakalar. iOS'tan farklı olarak
/// AVAudioSession kurmaya gerek yok.
///
/// MPVPlayer state'ini gözlemleyip metadata ve transport komutlarını sisteme bağlar.
@MainActor
final class NowPlayingCenter {
    private weak var player: MPVPlayer?
    private var cancellables: [AnyCancellable] = []
    private var commandsBound = false

    var nextHandler: (() -> Void)?
    var prevHandler: (() -> Void)?

    init(player: MPVPlayer) {
        self.player = player
        bindCommands()
        observePlayer()
    }

    deinit {
        // Player kaybolduktan sonra Now Playing'i temizle.
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        MPRemoteCommandCenter.shared().playCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().skipForwardCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().skipBackwardCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(nil)
    }

    func setMetadata(title: String, subtitle: String?, isLive: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
            MPNowPlayingInfoPropertyMediaType: NSNumber(value: MPNowPlayingInfoMediaType.video.rawValue)
        ]
        if let subtitle, !subtitle.isEmpty {
            info[MPMediaItemPropertyArtist] = subtitle
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Bindings

    private func bindCommands() {
        guard !commandsBound else { return }
        commandsBound = true
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.addTarget { [weak self] _ in
            self?.player?.play(); return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause(); return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let p = self?.player else { return .commandFailed }
            if p.isPaused { p.play() } else { p.pause() }
            return .success
        }
        cc.skipForwardCommand.preferredIntervals = [15]
        cc.skipForwardCommand.addTarget { [weak self] _ in
            guard let p = self?.player else { return .commandFailed }
            p.seek(to: p.position + 15)
            return .success
        }
        cc.skipBackwardCommand.preferredIntervals = [15]
        cc.skipBackwardCommand.addTarget { [weak self] _ in
            guard let p = self?.player else { return .commandFailed }
            p.seek(to: max(p.position - 15, 0))
            return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextHandler?(); return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.prevHandler?(); return .success
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let p = self?.player,
                  let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            p.seek(to: e.positionTime)
            return .success
        }
    }

    private func observePlayer() {
        guard let player else { return }

        player.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { paused in
                MPNowPlayingInfoCenter.default().playbackState = paused ? .paused : .playing
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(player.$position, player.$duration, player.$playbackRate)
            .receive(on: DispatchQueue.main)
            .sink { pos, dur, rate in
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = pos
                if dur.isFinite, dur > 0 { info[MPMediaItemPropertyPlaybackDuration] = dur }
                info[MPNowPlayingInfoPropertyPlaybackRate] = rate
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
            .store(in: &cancellables)
    }
}
