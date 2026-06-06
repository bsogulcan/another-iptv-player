import AppKit
import SwiftUI

/// Finder/Music tarzı çift tıklayarak disclosure toggle için NSEvent-tabanlı çözüm.
///
/// SwiftUI'nin `TapGesture(count: 2)` modifier'ı tek tıklamayı ~250ms (system double-click
/// interval) geciktiriyor çünkü ikinci tıklamayı bekliyor — native macOS sidebar bu davranışa
/// sahip değildir (NSOutlineView selection'ı mouseDown anında yapar, doubleAction sonradan
/// fires). SwiftUI bu API'yi expose etmediği için AppKit seviyesinde NSEvent monitor kullanıyoruz.
///
/// Akış: Her disclosure label `.onHover` ile "üzerimdeyken double click toggle bu callback'i
/// çağırsın" diye `Self.shared`'a kayıt yapar. ContentView'in `.onAppear`'ındaki
/// `NSEvent.addLocalMonitorForEvents(.leftMouseDown)` monitor'ı `clickCount == 2` olduğunda
/// kayıtlı toggle'ı çalıştırır. Tek tık native List selection'a gider — gesture pipeline'ı
/// dokunmaz, gecikme olmaz.
///
/// ID-tabanlı state: birden fazla row hover olabilir (mouse hızlı geçiyorsa hover-in/out sırası
/// karışır). Her row stable bir ID ile registreolur; hover-out yalnızca "halen aktif ID benim"
/// ise temizler. Bu sayede A→B geçişinde A'nın hover-out'u B'nin pendingToggle'ını silmez.
@MainActor
final class SidebarDoubleClickManager {
    static let shared = SidebarDoubleClickManager()
    private var currentId: AnyHashable?
    private var currentToggle: (() -> Void)?

    func registerHover<ID: Hashable>(id: ID, toggle: @escaping () -> Void) {
        currentId = AnyHashable(id)
        currentToggle = toggle
    }

    func clearHover<ID: Hashable>(id: ID) {
        if currentId == AnyHashable(id) {
            currentId = nil
            currentToggle = nil
        }
    }

    func fireIfHovering() {
        currentToggle?()
    }
}

extension View {
    /// Disclosure label'ları için: satır boyu hit area + hover ile toggle kaydı.
    /// `id` her satıra unique olmalı (örn. SidebarSelection enum case'i).
    func sidebarDoubleClickToggle<ID: Hashable>(id: ID, toggle: @escaping () -> Void) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    SidebarDoubleClickManager.shared.registerHover(id: id, toggle: toggle)
                } else {
                    SidebarDoubleClickManager.shared.clearHover(id: id)
                }
            }
    }
}
