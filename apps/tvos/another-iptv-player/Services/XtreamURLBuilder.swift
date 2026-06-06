import Foundation

enum XtreamURLBuilder {
    static func liveStream(playlist: Playlist, stream: DBLiveStream) -> URL? {
        let base = normalizedBase(playlist.serverURL)
        return URL(string: "\(base)/live/\(playlist.username)/\(playlist.password)/\(stream.streamId).ts")
    }

    static func movie(playlist: Playlist, stream: DBVODStream) -> URL? {
        let base = normalizedBase(playlist.serverURL)
        let ext = trimmed(stream.containerExtension) ?? "mp4"
        return URL(string: "\(base)/movie/\(playlist.username)/\(playlist.password)/\(stream.streamId).\(ext)")
    }

    static func episode(playlist: Playlist, episode: DBEpisode) -> URL? {
        let base = normalizedBase(playlist.serverURL)
        let streamId = trimmed(episode.episodeId) ?? episode.id
        let ext = trimmed(episode.containerExtension) ?? "mp4"
        return URL(string: "\(base)/series/\(playlist.username)/\(playlist.password)/\(streamId).\(ext)")
    }

    private static func normalizedBase(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
