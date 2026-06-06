import StoreKit
import UIKit

/// Uygulama içi App Store puanlama isteğini yönetir.
///
/// Strateji: kullanıcı belirli sayıda *başarılı oturum* (bir playlist dashboard'una
/// sorunsuz ulaşma) yaşadıktan sonra sistem puanlama diyaloğu istenir. Apple bu
/// diyaloğu yılda en fazla 3 kez gerçekten gösterir; bu yüzden istek kendi
/// tarafımızda da sürüm + tarih bazlı kapıda tutulur.
@MainActor
final class RatingManager {
    static let shared = RatingManager()
    private init() {}

    private let defaults = UserDefaults.standard

    private enum Key {
        static let sessionCount = "rating.successfulSessionCount"
        static let lastPromptVersion = "rating.lastPromptVersion"
        static let lastPromptDate = "rating.lastPromptDate"
    }

    /// İlk isteğin gösterileceği başarılı oturum eşiği.
    private let promptThreshold = 4
    /// İki istek arasındaki minimum gün.
    private let minDaysBetweenPrompts = 90

    /// Bu uygulama açılışında oturum zaten sayıldı mı? (açılış başına tek sayım)
    private var didCountThisLaunch = false

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Kullanıcı içeriğe ulaştığında (dashboard açıldığında) çağrılır.
    /// Uygulama açılışı başına yalnızca bir kez sayar.
    func registerSuccessfulSession() {
        if MockFixture.isActive { return }
        guard !didCountThisLaunch else { return }
        didCountThisLaunch = true
        let count = defaults.integer(forKey: Key.sessionCount) + 1
        defaults.set(count, forKey: Key.sessionCount)
    }

    /// Tüm koşullar uygunsa sistem puanlama diyaloğunu ister.
    /// Bir başarılı oturum tetiklendikten birkaç saniye sonra çağrılması önerilir.
    func requestReviewIfAppropriate() {
        if MockFixture.isActive { return }
        // Yalnızca bu açılışta gerçek bir oturum sayıldıysa devam et.
        guard didCountThisLaunch else { return }

        guard defaults.integer(forKey: Key.sessionCount) >= promptThreshold else { return }

        // Bu sürümde daha önce sorduysak tekrar sorma.
        guard defaults.string(forKey: Key.lastPromptVersion) != currentVersion else { return }

        // Son istekten bu yana yeterli süre geçmiş mi?
        if let last = defaults.object(forKey: Key.lastPromptDate) as? Date {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            guard days >= minDaysBetweenPrompts else { return }
        }

        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }

        AppStore.requestReview(in: scene)

        defaults.set(currentVersion, forKey: Key.lastPromptVersion)
        defaults.set(Date(), forKey: Key.lastPromptDate)
    }
}
