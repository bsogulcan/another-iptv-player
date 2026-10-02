import SwiftUI

private struct EPGLineReservedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether channel cards keep room for the now/next line under the channel name.
    /// Injected at the dashboard root next to `epgSnapshot`, from
    /// `EPGStore.isLineReserved(for:)`, which can answer before the store has loaded
    /// anything. A card that keys the line on the snapshot being there is laid out
    /// without it on its first frame and grows when the snapshot arrives; keyed on this
    /// it has its final height from the start and only the line's content changes.
    /// False outside a dashboard, and for a playlist without a guide.
    var epgLineReserved: Bool {
        get { self[EPGLineReservedKey.self] }
        set { self[EPGLineReservedKey.self] = newValue }
    }
}

private struct EPGGuideEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False while the TV guide of the open playlist is switched off in Settings, so
    /// screens can drop their guide entry points (the guide button, a channel's
    /// schedule) instead of opening an empty guide. Injected next to `epgLineReserved`
    /// from `EPGStore.isGuideEnabled`.
    var epgGuideEnabled: Bool {
        get { self[EPGGuideEnabledKey.self] }
        set { self[EPGGuideEnabledKey.self] = newValue }
    }
}
