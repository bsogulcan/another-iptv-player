import Foundation
import Combine
import SwiftUI

/// A version of the app published on the App Store that is newer than the running one.
struct AppStoreRelease: Equatable {
    let version: String
    let storeURL: URL
}

/// Asks the public App Store lookup endpoint which version is live and, when it is newer
/// than the running build (and installable on this OS), publishes it so the root view can
/// offer an update. The request carries only the bundle id and a country code — no device
/// or user identifiers.
@MainActor
final class AppUpdateChecker: ObservableObject {
    #if DEBUG
    static let shared = AppUpdateChecker(checksEnabled: false)
    #else
    static let shared = AppUpdateChecker()
    #endif

    @Published var availableUpdate: AppStoreRelease?
    /// Set by the dashboards while a player fills the screen. The offer waits until the
    /// player closes or shrinks to the mini card, so it never interrupts playback.
    @Published var isPlayerInFront = false

    /// Whether the root view should show the offer now.
    var shouldOfferUpdate: Bool { availableUpdate != nil && !isPlayerInFront }

    private let defaults: UserDefaults
    private let checksEnabled: Bool
    private let lookupURL: URL
    private let session: URLSession
    private enum Key {
        static let dismissedVersion = "update.dismissedVersion"
        static let dismissedDate = "update.dismissedDate"
    }

    /// After "Later", the same version is offered again only after this long.
    private let snoozeInterval: TimeInterval = 24 * 60 * 60
    /// Minimum time between two lookups while the app stays alive.
    private let checkInterval: TimeInterval = 12 * 60 * 60
    /// After a lookup that could not reach the store, the next try waits this long.
    private let retryInterval: TimeInterval = 60 * 60

    /// When the next lookup may run.
    private var nextCheck: Date?
    private var isChecking = false

    init(defaults: UserDefaults = .standard, checksEnabled: Bool = true,
         lookupURL: URL = URL(string: "https://itunes.apple.com/lookup")!, session: URLSession = .shared) {
        self.defaults = defaults
        self.checksEnabled = checksEnabled
        self.lookupURL = lookupURL
        self.session = session
    }

    static var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Called whenever the scene becomes active; throttled internally.
    @discardableResult
    func checkIfNeeded() -> Task<Void, Never>? {
        guard checksEnabled, !MockFixture.isActive else { return nil }
        guard !isChecking, availableUpdate == nil else { return nil }
        if let nextCheck, Date() < nextCheck { return nil }
        isChecking = true
        return Task {
            defer { isChecking = false }
            switch await fetchStoreRelease() {
            case .failed:
                // No answer from the store (offline, timeout): try again later, not on
                // every return to the app.
                nextCheck = Date().addingTimeInterval(retryInterval)
            case .noInstallableRelease:
                nextCheck = Date().addingTimeInterval(checkInterval)
            case .release(let release):
                nextCheck = Date().addingTimeInterval(checkInterval)
                guard Self.isVersion(release.version, newerThan: Self.installedVersion),
                      !isSnoozed(release.version) else { return }
                availableUpdate = release
            }
        }
    }

    func snooze(_ release: AppStoreRelease) {
        defaults.set(release.version, forKey: Key.dismissedVersion)
        defaults.set(Date(), forKey: Key.dismissedDate)
        availableUpdate = nil
    }

    private func isSnoozed(_ version: String) -> Bool {
        guard defaults.string(forKey: Key.dismissedVersion) == version,
              let date = defaults.object(forKey: Key.dismissedDate) as? Date else { return false }
        return Date().timeIntervalSince(date) < snoozeInterval
    }

    // MARK: - Lookup

    private struct LookupResponse: Decodable {
        struct Result: Decodable {
            let version: String
            let trackViewUrl: String
            let minimumOsVersion: String?
        }
        let results: [Result]
    }

    private enum LookupOutcome {
        case release(AppStoreRelease)
        /// The store answered: the app is not listed, or the live version needs a newer OS.
        case noInstallableRelease
        /// No usable answer from any storefront.
        case failed
    }

    /// The lookup is per storefront; the device region usually matches it. An empty or
    /// failed answer there falls back to the default (US) storefront.
    private func fetchStoreRelease() async -> LookupOutcome {
        guard let bundleID = Bundle.main.bundleIdentifier else { return .noInstallableRelease }
        var anyAnswer = false
        var countries: [String?] = [nil]
        if let region = Locale.current.region?.identifier, region.count == 2 {
            countries.insert(region.lowercased(), at: 0)
        }
        for country in countries {
            guard var components = URLComponents(url: lookupURL, resolvingAgainstBaseURL: false) else { return .failed }
            components.queryItems = [URLQueryItem(name: "bundleId", value: bundleID)]
            #if os(macOS)
            components.queryItems?.append(URLQueryItem(name: "entity", value: "macSoftware"))
            #endif
            if let country { components.queryItems?.append(URLQueryItem(name: "country", value: country)) }
            guard let url = components.url else { continue }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.httpMethod = "GET"
            // A failed storefront moves on to the next one, like an empty answer.
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(LookupResponse.self, from: data) else {
                continue
            }
            anyAnswer = true
            guard let result = decoded.results.first else { continue }
            let system = ProcessInfo.processInfo.operatingSystemVersion
            let systemVersion = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
            if let minimum = result.minimumOsVersion,
               Self.isVersion(minimum, newerThan: systemVersion) {
                return .noInstallableRelease
            }
            guard let storeURL = URL(string: result.trackViewUrl) else { continue }
            return .release(AppStoreRelease(version: result.version, storeURL: storeURL))
        }
        return anyAnswer ? .noInstallableRelease : .failed
    }

    /// Numeric, component-wise comparison; missing components count as 0 ("3.1" == "3.1.0").
    nonisolated static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        func parts(_ value: String) -> [Int] {
            value.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(lhs), b = parts(rhs)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}

struct AppUpdateOffer: ViewModifier {
    @ObservedObject var updateChecker: AppUpdateChecker
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .alert(
                L("update.title"),
                isPresented: Binding(
                    get: { updateChecker.shouldOfferUpdate },
                    // A player coming to the front hides the offer without answering it;
                    // it is shown again once the player is gone.
                    set: { if !$0, !updateChecker.isPlayerInFront { updateChecker.availableUpdate = nil } }
                ),
                presenting: updateChecker.availableUpdate
            ) { release in
                Button(L("update.action")) {
                    openURL(release.storeURL)
                    updateChecker.availableUpdate = nil
                }
                Button(L("update.later"), role: .cancel) {
                    updateChecker.snooze(release)
                }
            } message: { release in
                Text(L("update.message", release.version, AppUpdateChecker.installedVersion))
            }
    }
}
