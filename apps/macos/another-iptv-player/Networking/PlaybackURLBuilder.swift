import Foundation

struct PlaybackURLBuilder {
    let playlist: Playlist
    
    private var cleanBaseURL: String {
        var baseString = playlist.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !baseString.lowercased().hasPrefix("http://") && !baseString.lowercased().hasPrefix("https://") {
            baseString = "http://\(baseString)"
        }
        
        // Remove trailing slash
        if baseString.hasSuffix("/") {
            baseString.removeLast()
        }
        
        // Remove player_api.php if user entered it
        if baseString.lowercased().hasSuffix("/player_api.php") {
            baseString = String(baseString.dropLast(15))
        } else if baseString.lowercased().hasSuffix("player_api.php") {
            baseString = String(baseString.dropLast(14))
        }
        
        return baseString.replacingOccurrences(of: " ", with: "")
    }
    
    private var authPath: String {
        let u = playlist.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = playlist.password.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(u)/\(p)"
    }
    
    /// Builds URL for a live stream. Xtream API direct playback format uses server/u/p/id.
    func liveURL(streamId: Int, extension: String? = nil) -> URL? {
        var urlString = "\(cleanBaseURL)/\(authPath)/\(streamId)"
        if let ext = `extension`, !ext.isEmpty {
            urlString += ".\(ext)"
        }
        return URL(string: urlString)
    }
    
    /// Builds URL for a VOD (Movie).
    func movieURL(streamId: Int, containerExtension: String?) -> URL? {
        if let mock = MockFixture.demoPlaybackURL(playlistId: playlist.id) { return mock }
        let ext = containerExtension ?? "mp4"
        let urlString = "\(cleanBaseURL)/movie/\(authPath)/\(streamId).\(ext)"
        return URL(string: urlString)
    }

    /// Builds URL for a series episode.
    func seriesURL(streamId: String, containerExtension: String?) -> URL? {
        if let mock = MockFixture.demoPlaybackURL(playlistId: playlist.id) { return mock }
        let ext = containerExtension ?? "mp4"
        let urlString = "\(cleanBaseURL)/series/\(authPath)/\(streamId).\(ext)"
        return URL(string: urlString)
    }
}
