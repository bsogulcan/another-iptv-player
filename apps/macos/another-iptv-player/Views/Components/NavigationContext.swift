import Combine
import SwiftUI

/// Closure-based NavigationLink push'larını NavigationStack(path:) bağlı binding'e
/// yansıtmıyor — depth tracking için detail view'lar onAppear/onDisappear ile
/// bu singleton'a sinyal verir. DashboardView outer toolbar'ı buradan okur.
@MainActor
final class NavigationContext: ObservableObject {
    static let shared = NavigationContext()

    @Published private(set) var depth: Int = 0

    func push() {
        depth += 1
    }

    func pop() {
        depth = max(0, depth - 1)
    }

    /// Tab değişiminde tüm depth sıfırlanır (kullanıcı detail view'dayken sidebar'dan
    /// farklı tab'a geçerse counter takılı kalmasın).
    func reset() {
        depth = 0
    }
}

/// Detail view'lara takılan modifier — push/pop için lifecycle hook'u.
struct DetailDepthTracker: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { NavigationContext.shared.push() }
            .onDisappear { NavigationContext.shared.pop() }
    }
}

extension View {
    /// Detail view'lara uygula — depth'i 1 artırır, view kaybolunca 1 azaltır.
    func trackDetailDepth() -> some View {
        modifier(DetailDepthTracker())
    }
}
