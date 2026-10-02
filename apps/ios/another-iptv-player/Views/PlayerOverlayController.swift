import Combine
import SwiftUI

/// Dashboard `ZStack` üzerinde tutulur; sürükleyerek kapatırken alttaki sekme içeriği görünür.
struct PlayerOverlayPresentation: Identifiable {
    let id = UUID()
    let root: AnyView
    let onDismiss: (() -> Void)?
}

/// Whether the active player fills the screen or is shrunk into the floating mini card.
enum PlayerOverlayMode: Equatable {
    case fullscreen
    case mini
}

final class PlayerOverlayController: ObservableObject {
    @Published var presentation: PlayerOverlayPresentation?
    /// Aktif indirme varken gösterilen onay alert'i için tutulan bekleyen sunum.
    @Published var pendingPresentation: PlayerOverlayPresentation?
    /// Fullscreen vs. floating mini player. Reset to `.fullscreen` on every new presentation.
    @Published var mode: PlayerOverlayMode = .fullscreen

    /// Aynı playlist'te aktif indirme varsa kullanıcıya onay sorar (sunucu connection limiti çakışmasın).
    /// Başka playlist'in indirmesi etki etmez.
    /// `skipDownloadCheck = true` → lokal dosya oynatımı için kontrolü atlar.
    /// `playlistId` verilmezse uyarı gösterilmez (M3U / playlist-bağımsız oynatım için).
    @MainActor
    func present<Content: View>(
        onDismiss: (() -> Void)? = nil,
        skipDownloadCheck: Bool = false,
        playlistId: UUID? = nil,
        @ViewBuilder content: () -> Content
    ) {
        // The overlay is a SwiftUI sibling inside the dashboard window, so it sits below the
        // software keyboard. End editing before anything else — also ahead of the
        // download-warning branch: UIKit restores the first responder when an alert closes,
        // so resigning only on confirm would let the keyboard come back over the player.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        let pkg = PlayerOverlayPresentation(root: AnyView(content()), onDismiss: onDismiss)
        let shouldWarn: Bool = {
            if skipDownloadCheck { return false }
            guard let playlistId else { return false }
            return DownloadManager.shared.hasActiveDownload(playlistId: playlistId)
        }()
        if shouldWarn {
            pendingPresentation = pkg
        } else {
            // A new stream always opens fullscreen, even if a mini player was showing.
            // Overlay hosts pass pkg.id as an environment revision while preserving the
            // PlayerView/VideoPlayerController identity (required for AirPlay continuity).
            mode = .fullscreen
            presentation = pkg
        }
    }

    func confirmPending() {
        guard let pending = pendingPresentation else { return }
        pendingPresentation = nil
        mode = .fullscreen
        presentation = pending
    }

    func cancelPending() {
        pendingPresentation = nil
    }

    func dismiss(animated _: Bool = true) {
        let callback = presentation?.onDismiss
        // Keep `mode` as-is through removal so the exit transition matches the current mode
        // (a mini card fades, a fullscreen player slides down). `mode` is reset by the next
        // `present()` / `confirmPending()`, before any new content is shown.
        presentation = nil
        callback?()
    }

    /// Dismisses only while `id` is still the presentation on screen. The player's own
    /// exits finish after a short animation; by then a newer item may have been
    /// presented, and a late dismiss must not close that one.
    func dismiss(presentationID id: UUID) {
        guard presentation?.id == id else { return }
        dismiss()
    }

    /// Shrink the active player into the floating mini card (no teardown).
    @MainActor
    func minimize() {
        guard presentation != nil else { return }
        mode = .mini
    }

    /// Grow the mini card back to fullscreen.
    @MainActor
    func expand() {
        guard presentation != nil else { return }
        mode = .fullscreen
    }
}

private struct PlayerOverlayDismissKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct PlayerOverlayModeKey: EnvironmentKey {
    static let defaultValue: PlayerOverlayMode = .fullscreen
}

private struct PlayerOverlayPresentationIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

private struct PlayerOverlayMinimizeKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct PlayerOverlayExpandKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Overlay modunda `PlayerView` kapatma; yoksa `dismiss()` kullanılır.
    var playerOverlayDismiss: (() -> Void)? {
        get { self[PlayerOverlayDismissKey.self] }
        set { self[PlayerOverlayDismissKey.self] = newValue }
    }

    /// Current fullscreen/mini mode of the overlay-hosted player.
    var playerOverlayMode: PlayerOverlayMode {
        get { self[PlayerOverlayModeKey.self] }
        set { self[PlayerOverlayModeKey.self] = newValue }
    }

    /// Changes whenever the overlay receives a newly selected playback item.
    /// PlayerView observes this explicit revision while keeping its StateObject
    /// (and therefore an active AirPlay AVPlayer) alive across content changes.
    var playerOverlayPresentationID: UUID? {
        get { self[PlayerOverlayPresentationIDKey.self] }
        set { self[PlayerOverlayPresentationIDKey.self] = newValue }
    }

    /// Request shrinking the player to the mini card. `nil` when not overlay-hosted.
    var playerOverlayMinimize: (() -> Void)? {
        get { self[PlayerOverlayMinimizeKey.self] }
        set { self[PlayerOverlayMinimizeKey.self] = newValue }
    }

    /// Request growing the mini card back to fullscreen. `nil` when not overlay-hosted.
    var playerOverlayExpand: (() -> Void)? {
        get { self[PlayerOverlayExpandKey.self] }
        set { self[PlayerOverlayExpandKey.self] = newValue }
    }
}
