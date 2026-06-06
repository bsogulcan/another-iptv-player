import StoreKit

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

    private let promptThreshold = 4
    private let minDaysBetweenPrompts = 90

    private var didCountThisLaunch = false

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func registerSuccessfulSession() {
        if MockFixture.isActive { return }
        guard !didCountThisLaunch else { return }
        didCountThisLaunch = true
        let count = defaults.integer(forKey: Key.sessionCount) + 1
        defaults.set(count, forKey: Key.sessionCount)
    }

    func requestReviewIfAppropriate() {
        if MockFixture.isActive { return }
        guard didCountThisLaunch else { return }
        guard defaults.integer(forKey: Key.sessionCount) >= promptThreshold else { return }
        guard defaults.string(forKey: Key.lastPromptVersion) != currentVersion else { return }
        if let last = defaults.object(forKey: Key.lastPromptDate) as? Date {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            guard days >= minDaysBetweenPrompts else { return }
        }

        // macOS: legacy `SKStoreReviewController.requestReview()` deprecated ama 11+ çalışır.
        // Modern `AppStore.requestReview(in:)` macOS'ta SwiftUI environment yolu gerektiriyor;
        // RatingManager non-SwiftUI olduğu için legacy yolu tercih ediyoruz.
        SKStoreReviewController.requestReview()

        defaults.set(currentVersion, forKey: Key.lastPromptVersion)
        defaults.set(Date(), forKey: Key.lastPromptDate)
    }
}
