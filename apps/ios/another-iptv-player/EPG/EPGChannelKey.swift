import Foundation

/// Resolves a playlist channel to the key used to look up EPG now/next in the
/// snapshot. Prefers the explicit EPG id, falling back to the channel name (the
/// store publishes both id and name aliases for display-name-matched channels).
/// `nonisolated` so the M3U player-panel builders (which are `nonisolated`) can
/// call it.
nonisolated enum EPGChannelKey {
    static func forXtream(_ stream: DBLiveStream) -> String? {
        EPGConstants.normalizeChannelKey(stream.epgChannelId) ?? EPGConstants.normalizeChannelKey(stream.name)
    }

    static func forM3U(_ channel: DBM3UChannel) -> String? {
        EPGConstants.normalizeChannelKey(channel.tvgId) ?? EPGConstants.normalizeChannelKey(channel.tvgName ?? channel.name)
    }
}
