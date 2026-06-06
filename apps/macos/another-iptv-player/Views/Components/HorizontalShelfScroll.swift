import AppKit
import SwiftUI

/// macOS-uyumlu yatay scroll: native `ScrollView(.horizontal)` mouse wheel'i
/// otomatik yataya çevirmiyor (sadece trackpad / Shift+wheel). Bu NSScrollView
/// wrapper'ı dikey wheel input'unu yatay scroll'a çevirir.
struct HorizontalShelfScroll<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = AutoHorizontalScrollView()
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none

        let host = NSHostingController(rootView: AnyView(content()))
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = host.view

        // Yükseklik scroll view'a sabit, genişlik içeriğin intrinsic'i.
        NSLayoutConstraint.activate([
            host.view.heightAnchor.constraint(equalTo: scroll.heightAnchor),
            host.view.topAnchor.constraint(equalTo: scroll.topAnchor)
        ])

        context.coordinator.host = host
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.host?.rootView = AnyView(content())
    }

    func makeCoordinator() -> HorizontalShelfCoordinator { HorizontalShelfCoordinator() }
}

/// `HorizontalShelfScroll`'un coordinator'ı. Generic `<Content>` struct'ın içine nested
/// class olarak konsa Swift 6.2 Release optimization deinit IR emission'da crash'ediyor —
/// top-level non-generic class olarak ayrı tutmak compiler bug'ını bypass eder.
final class HorizontalShelfCoordinator {
    var host: NSHostingController<AnyView>?
}

/// Yatay scroll'u **yalnızca gerçek yatay input** (trackpad yatay gesture, Shift+wheel) ile yapar.
/// Dikey input (mouse wheel + trackpad dikey gesture) parent'a forward edilir → sayfa dikey scroll'u çalışır.
/// Kategori shelf'leri ok'larla sayfalanır; mouse wheel ile yatay kaydırma davranışı **kaldırıldı**.
final class AutoHorizontalScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // Yatay delta dominant: native handler (gerçek yatay gesture / Shift+wheel).
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            super.scrollWheel(with: event)
            return
        }
        // Dikey-dominant input → her zaman parent'a forward (sayfa dikey scroll'u).
        nextResponder?.scrollWheel(with: event)
    }
}
