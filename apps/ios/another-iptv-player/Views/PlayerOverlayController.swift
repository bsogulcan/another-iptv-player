import Combine
import GRDB
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

/// The detail page a player asks for when its title is tapped and the screen that started
/// playback cannot show it any more (another tab is selected, the origin was popped, or it
/// was a sheet that closed when playback began).
enum PlayerDetailRequest: Equatable {
    case movie(DBVODStream)
    case series(DBSeries)
}

final class PlayerOverlayController: ObservableObject {
    @Published var presentation: PlayerOverlayPresentation?
    /// Aktif indirme varken gösterilen onay alert'i için tutulan bekleyen sunum.
    @Published var pendingPresentation: PlayerOverlayPresentation?
    /// Fullscreen vs. floating mini player. Reset to `.fullscreen` on every new presentation.
    @Published var mode: PlayerOverlayMode = .fullscreen
    /// Set by `requestDetail`. The dashboard selects the tab that owns the item; that tab's
    /// root pushes the page and sets this back to nil. It stays set until then, so a tab
    /// that is only mounted by the switch still finds it.
    @Published var detailRequest: PlayerDetailRequest?

    private let database: AppDatabase

    /// The dashboards use the app database; tests pass their own.
    init(database: AppDatabase = .shared) {
        self.database = database
    }

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
        endEditing()
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

    /// Swaps what the mounted player shows for a continuation of the same session: the next
    /// or previous episode, or the same item with refreshed neighbours. Unlike `present()`
    /// this is not a user pick, so nothing around the player may change: a docked card stays
    /// docked, a search field keeps its keyboard, and the download warning the user already
    /// answered is not asked again. The presentation still gets a new id, which is what tells
    /// the mounted `PlayerView` to adopt the new item.
    /// Does nothing once the player has been closed, so a late continuation cannot reopen it.
    @MainActor
    func replaceContent<Content: View>(
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        guard presentation != nil else { return }
        presentation = PlayerOverlayPresentation(root: AnyView(content()), onDismiss: onDismiss)
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
        // The card can be tapped while a search field is being edited (it docks above the
        // keyboard). Fullscreen is laid out behind the keyboard, so editing ends first.
        endEditing()
        mode = .fullscreen
    }

    /// Resigns whatever text field is first responder. The search text and the active
    /// search stay as they are.
    private func endEditing() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    // MARK: - Detail request

    /// Looks up the item a player's title tap names and publishes it as `detailRequest`.
    /// `type` and `id` are what the player hands to its title tap: "vod" with a stream id,
    /// "series" with a series id. Anything else, or an item that is no longer in the
    /// playlist, leaves the request untouched.
    @MainActor
    func requestDetail(type: String, id: String, playlistId: UUID) async {
        guard let numericId = Int(id) else { return }
        let found: PlayerDetailRequest?
        switch type {
        case "vod":
            let movie = try? await database.read { db in
                try DBVODStream
                    .filter(Column("streamId") == numericId && Column("playlistId") == playlistId)
                    .fetchOne(db)
            }
            found = movie.map(PlayerDetailRequest.movie)
        case "series":
            let series = try? await database.read { db in
                try DBSeries
                    .filter(Column("seriesId") == numericId && Column("playlistId") == playlistId)
                    .fetchOne(db)
            }
            found = series.map(PlayerDetailRequest.series)
        default:
            found = nil
        }
        guard let found else { return }
        detailRequest = found
    }
}

// MARK: - Overlay host

/// Draws the presented player above a dashboard's tabs. It is a view of its own, observing
/// the controller itself, so that the environment closures below are rebuilt only when the
/// overlay changes. Built inline in a dashboard body they would be new values on every tab
/// switch and every catalog or guide publish, and each time re-run the mounted player.
/// The dashboard keeps `.zIndex` at the call site.
struct PlayerOverlayHost: View {
    @ObservedObject var controller: PlayerOverlayController

    var body: some View {
        ZStack {
            if let item = controller.presentation {
                item.root
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Bound to this presentation: a dismiss the player issues at the
                    // end of its exit animation cannot close an item presented since.
                    .environment(\.playerOverlayDismiss) {
                        controller.dismiss(presentationID: item.id)
                    }
                    .environment(\.playerOverlayMode, controller.mode)
                    .environment(\.playerOverlayPresentationID, item.id)
                    .environment(\.playerOverlayMinimize) { controller.minimize() }
                    .environment(\.playerOverlayExpand) { controller.expand() }
                    // VoiceOver's two-finger scrub leaves the player the way a system
                    // presentation would. Kept unconditional: wrapping item.root in an
                    // if/else would remount PlayerView and tear playback down.
                    .accessibilityAction(.escape) { controller.minimize() }
                    // Keep UIKit-backed video surfaces at a fixed geometry while they attach.
                    // Moving the whole AVPlayer/KSPlayer subtree produced a launch flash.
                    .transition(.opacity)
            }
        }
        // The player must not be laid out in the keyboard-reduced area: a keyboard that is
        // still animating out would otherwise resize it and push the chrome up.
        // Fullscreen only: the docked mini card has to stay above the keyboard. The
        // modifier itself stays unconditional so PlayerView is never remounted.
        .ignoresSafeArea(.keyboard, edges: controller.mode == .mini ? [] : .all)
        // Animate only insertion/removal. A source switch changes presentation.id while
        // preserving PlayerView identity and must not animate the entire player subtree.
        .animation(.easeOut(duration: 0.14), value: controller.presentation != nil)
    }
}

// MARK: - Environment

private struct PlayerOverlayControllerKey: EnvironmentKey {
    static let defaultValue: PlayerOverlayController? = nil
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
    /// The dashboard's overlay controller, for views that only call it (`present`,
    /// `replaceContent`, `dismiss`, `requestDetail`). Reading it does not subscribe the view,
    /// unlike `@EnvironmentObject`, which re-runs every mounted screen on each open,
    /// minimise, expand and close. The reference is stable for a dashboard's lifetime.
    /// A view tree outside the dashboard's own (a sheet) has to be handed the value again.
    var playerOverlayController: PlayerOverlayController? {
        get { self[PlayerOverlayControllerKey.self] }
        set { self[PlayerOverlayControllerKey.self] = newValue }
    }

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

// MARK: - Detail request delivery

/// Hands a waiting detail request to the screen that can show it.
private struct PlayerDetailRequestModifier: ViewModifier {
    let controller: PlayerOverlayController?
    let action: (PlayerDetailRequest) -> Bool

    func body(content: Content) -> some View {
        content.onReceive(requests) { request in
            // Another screen may have taken it, or a newer one replaced it, since it was sent.
            guard let controller, controller.detailRequest == request else { return }
            if action(request) { controller.detailRequest = nil }
        }
    }

    private var requests: AnyPublisher<PlayerDetailRequest, Never> {
        guard let controller else { return Empty().eraseToAnyPublisher() }
        return controller.$detailRequest
            .compactMap { $0 }
            // @Published sends a value before it is stored. Delivered in the same turn, the
            // receiver's `detailRequest = nil` would be overwritten by the value being set.
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

extension View {
    /// Calls `action` with the controller's pending detail request: the one waiting when
    /// this view is mounted, and every one that arrives while it is. Return true when the
    /// view shows the page; the request is then cleared. Return false to leave it for the
    /// screen it is meant for.
    /// A view that reads the controller from `\.playerOverlayController` is not re-run when
    /// the controller changes, so `.onChange(of: controller.detailRequest)` never fires
    /// there; this subscribes to the one property without subscribing the view.
    func onPlayerDetailRequest(
        from controller: PlayerOverlayController?,
        perform action: @escaping (PlayerDetailRequest) -> Bool
    ) -> some View {
        modifier(PlayerDetailRequestModifier(controller: controller, action: action))
    }
}

extension Optional where Wrapped == PlayerOverlayController {
    /// The controller for a call that has to reach it: `playerOverlay.injected?.present { … }`.
    /// With an optional environment value a screen mounted without the injection would
    /// ignore play taps silently; debug builds stop here instead.
    var injected: PlayerOverlayController? {
        assert(self != nil, "playerOverlayController is missing from this view's environment")
        return self
    }
}
