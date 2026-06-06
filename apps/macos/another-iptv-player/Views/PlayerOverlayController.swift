import Combine
import SwiftUI

/// ContentView'in detail panel ZStack'i içinde tutulur; sidebar görünür kalır,
/// kullanıcı oynatma sürerken başka bir kanala/filme geçebilir.
struct PlayerOverlayPresentation: Identifiable {
    let id = UUID()
    let root: AnyView
    let onDismiss: (() -> Void)?
}

final class PlayerOverlayController: ObservableObject {
    /// Singleton — SwiftUI @EnvironmentObject NSHostingController içinde
    /// (NSTabViewController + NavigationStack push) chronically env'i kaybediyor.
    /// Tek player olduğu için (modal overlay) singleton güvenli.
    static let shared = PlayerOverlayController()

    @Published var presentation: PlayerOverlayPresentation?
    /// Aktif indirme varken gösterilen onay alert'i için tutulan bekleyen sunum.
    @Published var pendingPresentation: PlayerOverlayPresentation?
    /// Detail panel ZStack'inde aynı id ile yeniden render olunca SwiftUI view'ı tutuyordu;
    /// ContentView `.id(item.id)` modifier'ı ile fresh instance zorluyor. (Bilgi notu)

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
        let pkg = PlayerOverlayPresentation(root: AnyView(content()), onDismiss: onDismiss)
        let shouldWarn: Bool = {
            if skipDownloadCheck { return false }
            guard let playlistId else { return false }
            return DownloadManager.shared.hasActiveDownload(playlistId: playlistId)
        }()
        if shouldWarn {
            pendingPresentation = pkg
        } else {
            presentation = pkg
        }
    }

    func confirmPending() {
        guard let pending = pendingPresentation else { return }
        pendingPresentation = nil
        presentation = pending
    }

    func cancelPending() {
        pendingPresentation = nil
    }

    func dismiss(animated _: Bool = true) {
        let callback = presentation?.onDismiss
        presentation = nil
        callback?()
    }
}

private struct PlayerOverlayDismissKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Overlay modunda `PlayerView` kapatma; yoksa `dismiss()` kullanılır.
    var playerOverlayDismiss: (() -> Void)? {
        get { self[PlayerOverlayDismissKey.self] }
        set { self[PlayerOverlayDismissKey.self] = newValue }
    }
}
