import Foundation

// MARK: - Safe Decoder Extension
extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: K) -> String? {
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return stringValue
        } else if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        } else if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return String(doubleValue)
        }
        return nil
    }
    
    func decodeFlexibleIntIfPresent(forKey key: K) -> Int? {
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return intValue
        } else if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Int(stringValue)
        } else if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(doubleValue)
        }
        return nil
    }
}

// MARK: - Auth
struct XtreamAuthResponse: Codable {
    let userInfo: XtreamUserInfo?
    let serverInfo: XtreamServerInfo?
    
    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }
    
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        userInfo = try? container?.decodeIfPresent(XtreamUserInfo.self, forKey: .userInfo)
        serverInfo = try? container?.decodeIfPresent(XtreamServerInfo.self, forKey: .serverInfo)
    }
}

struct XtreamUserInfo: Codable {
    let username: String?
    let password: String?
    let message: String?
    let auth: Int?
    let status: String?
    let expDate: String?
    let isTrial: String?
    let activeCons: String?
    let createdAt: String?
    let maxConnections: String?
    
    enum CodingKeys: String, CodingKey {
        case username, password, message, auth, status
        case expDate = "exp_date"
        case isTrial = "is_trial"
        case activeCons = "active_cons"
        case createdAt = "created_at"
        case maxConnections = "max_connections"
    }
    
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        username = container?.decodeFlexibleStringIfPresent(forKey: .username)
        password = container?.decodeFlexibleStringIfPresent(forKey: .password)
        message = container?.decodeFlexibleStringIfPresent(forKey: .message)
        auth = container?.decodeFlexibleIntIfPresent(forKey: .auth)
        status = container?.decodeFlexibleStringIfPresent(forKey: .status)
        expDate = container?.decodeFlexibleStringIfPresent(forKey: .expDate)
        isTrial = container?.decodeFlexibleStringIfPresent(forKey: .isTrial)
        activeCons = container?.decodeFlexibleStringIfPresent(forKey: .activeCons)
        createdAt = container?.decodeFlexibleStringIfPresent(forKey: .createdAt)
        maxConnections = container?.decodeFlexibleStringIfPresent(forKey: .maxConnections)
    }
}

struct XtreamServerInfo: Codable {
    let url: String?
    let port: String?
    let httpsPort: String?
    let serverProtocol: String?
    let rtmpPort: String?
    let timezone: String?
    let timeNow: String?
    
    enum CodingKeys: String, CodingKey {
        case url, port
        case httpsPort = "https_port"
        case serverProtocol = "server_protocol"
        case rtmpPort = "rtmp_port"
        case timezone
        case timeNow = "time_now"
    }
    
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        url = container?.decodeFlexibleStringIfPresent(forKey: .url)
        port = container?.decodeFlexibleStringIfPresent(forKey: .port)
        httpsPort = container?.decodeFlexibleStringIfPresent(forKey: .httpsPort)
        serverProtocol = container?.decodeFlexibleStringIfPresent(forKey: .serverProtocol)
        rtmpPort = container?.decodeFlexibleStringIfPresent(forKey: .rtmpPort)
        timezone = container?.decodeFlexibleStringIfPresent(forKey: .timezone)
        timeNow = container?.decodeFlexibleStringIfPresent(forKey: .timeNow)
    }
}

// MARK: - Category
struct XtreamCategory: Codable, Identifiable {
    let categoryId: String?
    let categoryName: String?
    let parentId: Int?
    
    var id: String { categoryId ?? UUID().uuidString }
    
    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
        case parentId = "parent_id"
    }
    
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        categoryId = container?.decodeFlexibleStringIfPresent(forKey: .categoryId)
        categoryName = container?.decodeFlexibleStringIfPresent(forKey: .categoryName)
        parentId = container?.decodeFlexibleIntIfPresent(forKey: .parentId)
    }
}

// MARK: - Streams
struct XtreamLiveStream: Codable, Identifiable {
    let streamId: Int?
    let streamIcon: String?
    let epgChannelId: String?
    let name: String?
    let categoryId: String?
    let isAdult: Int?

    var id: Int { streamId ?? 0 }

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case streamIcon = "stream_icon"
        case epgChannelId = "epg_channel_id"
        case name
        case categoryId = "category_id"
        case isAdult = "is_adult"
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        streamId = container?.decodeFlexibleIntIfPresent(forKey: .streamId)
        streamIcon = container?.decodeFlexibleStringIfPresent(forKey: .streamIcon)
        epgChannelId = container?.decodeFlexibleStringIfPresent(forKey: .epgChannelId)
        name = container?.decodeFlexibleStringIfPresent(forKey: .name)
        categoryId = container?.decodeFlexibleStringIfPresent(forKey: .categoryId)
        isAdult = container?.decodeFlexibleIntIfPresent(forKey: .isAdult)
    }
}

struct XtreamVODStream: Codable, Identifiable {
    let streamId: Int?
    let name: String?
    let streamIcon: String?
    let categoryId: String?
    let rating: String?
    let containerExtension: String?
    let isAdult: Int?
    let added: String?

    var id: Int { streamId ?? 0 }

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case categoryId = "category_id"
        case rating
        case containerExtension = "container_extension"
        case isAdult = "is_adult"
        case added
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        streamId = container?.decodeFlexibleIntIfPresent(forKey: .streamId)
        name = container?.decodeFlexibleStringIfPresent(forKey: .name)
        streamIcon = container?.decodeFlexibleStringIfPresent(forKey: .streamIcon)
        categoryId = container?.decodeFlexibleStringIfPresent(forKey: .categoryId)
        rating = container?.decodeFlexibleStringIfPresent(forKey: .rating)
        containerExtension = container?.decodeFlexibleStringIfPresent(forKey: .containerExtension)
        isAdult = container?.decodeFlexibleIntIfPresent(forKey: .isAdult)
        added = container?.decodeFlexibleStringIfPresent(forKey: .added)
    }
}

struct XtreamSeries: Codable, Identifiable {
    let seriesId: Int?
    let name: String?
    let cover: String?
    let plot: String?
    let cast: String?
    let director: String?
    let genre: String?
    let releaseDate: String?
    let rating: String?
    let categoryId: String?
    let youtubeTrailer: String?
    let lastModified: String?

    var id: Int { seriesId ?? 0 }

    enum CodingKeys: String, CodingKey {
        case seriesId = "series_id"
        case name, cover, plot, cast, director, genre, rating
        case categoryId = "category_id"
        case releaseDate = "releaseDate"
        case youtubeTrailer = "youtube_trailer"
        case lastModified = "last_modified"
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        seriesId = container?.decodeFlexibleIntIfPresent(forKey: .seriesId)
        name = container?.decodeFlexibleStringIfPresent(forKey: .name)
        cover = container?.decodeFlexibleStringIfPresent(forKey: .cover)
        plot = container?.decodeFlexibleStringIfPresent(forKey: .plot)
        cast = container?.decodeFlexibleStringIfPresent(forKey: .cast)
        director = container?.decodeFlexibleStringIfPresent(forKey: .director)
        genre = container?.decodeFlexibleStringIfPresent(forKey: .genre)
        rating = container?.decodeFlexibleStringIfPresent(forKey: .rating)
        categoryId = container?.decodeFlexibleStringIfPresent(forKey: .categoryId)
        releaseDate = container?.decodeFlexibleStringIfPresent(forKey: .releaseDate)
        youtubeTrailer = container?.decodeFlexibleStringIfPresent(forKey: .youtubeTrailer)
        lastModified = container?.decodeFlexibleStringIfPresent(forKey: .lastModified)
    }
}

// MARK: - Error-Safe Decodable
struct FailableDecodable<Base: Decodable>: Decodable {
    let base: Base?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.base = try? container.decode(Base.self)
    }
}

// MARK: - Series Info
struct XtreamSeriesInfoResponse: Codable {
    let seasons: [XtreamSeason]?
    let info: XtreamSeriesDetails?
    let episodes: [String: [XtreamEpisode]]?

    enum CodingKeys: String, CodingKey {
        case seasons, info, episodes
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        info = (try? container?.decodeIfPresent(XtreamSeriesDetails.self, forKey: .info)) ?? nil

        // Skip unparseable season entries so one bad item doesn't drop the whole list.
        do {
            if let wrapped = try container?.decodeIfPresent([FailableDecodable<XtreamSeason>].self, forKey: .seasons) {
                seasons = wrapped.compactMap { $0.base }
            } else {
                seasons = nil
            }
        } catch {
            #if DEBUG
            print("[SeriesInfo] seasons decode failed: \(error)")
            #endif
            seasons = nil
        }

        // Some Xtream servers return `episodes: []` (array) when empty instead of `{}` (object).
        // That would throw on synthesized Codable — treat any non-dict shape as empty.
        do {
            if let wrappedDict = try container?.decodeIfPresent([String: [FailableDecodable<XtreamEpisode>]].self, forKey: .episodes) {
                episodes = wrappedDict.mapValues { $0.compactMap { $0.base } }
            } else {
                episodes = nil
            }
        } catch {
            #if DEBUG
            print("[SeriesInfo] episodes decode as dict failed (\(error)) — trying empty-array fallback")
            #endif
            episodes = nil
        }
    }
}

struct XtreamSeriesDetails: Codable {
    let name: String?
    let cover: String?
    let plot: String?
    let cast: String?
    let director: String?
    let genre: String?
    let releaseDate: String?
    let rating: String?
    let lastModified: String?
    let rating5Based: Double?
    let backdropPath: [String]?
    let youtubeTrailer: String?
    let episodeRunTime: String?
    
    enum CodingKeys: String, CodingKey {
        case name, cover, plot, cast, director, genre, rating
        case releaseDate = "releaseDate"
        case lastModified = "last_modified"
        case rating5Based = "rating_5based"
        case backdropPath = "backdrop_path"
        case youtubeTrailer = "youtube_trailer"
        case episodeRunTime = "episode_run_time"
    }
    
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        name = container?.decodeFlexibleStringIfPresent(forKey: .name)
        cover = container?.decodeFlexibleStringIfPresent(forKey: .cover)
        plot = container?.decodeFlexibleStringIfPresent(forKey: .plot)
        cast = container?.decodeFlexibleStringIfPresent(forKey: .cast)
        director = container?.decodeFlexibleStringIfPresent(forKey: .director)
        genre = container?.decodeFlexibleStringIfPresent(forKey: .genre)
        rating = container?.decodeFlexibleStringIfPresent(forKey: .rating)
        releaseDate = container?.decodeFlexibleStringIfPresent(forKey: .releaseDate)
        lastModified = container?.decodeFlexibleStringIfPresent(forKey: .lastModified)
        rating5Based = try? container?.decodeIfPresent(Double.self, forKey: .rating5Based)
        backdropPath = try? container?.decodeIfPresent([String].self, forKey: .backdropPath)
        youtubeTrailer = container?.decodeFlexibleStringIfPresent(forKey: .youtubeTrailer)
        episodeRunTime = container?.decodeFlexibleStringIfPresent(forKey: .episodeRunTime)
    }
}

struct XtreamSeason: Codable, Identifiable {
    let name: String?
    let seasonNumber: Int?
    let cover: String?
    let overview: String?
    let airDate: String?
    let episodeCount: Int?
    let voteAverage: Double?
    
    // Xtream uses season number for some things, but let's give a default ID
    var id: String { "\(seasonNumber ?? 0)" }
    
    enum CodingKeys: String, CodingKey {
        case name
        case seasonNumber = "season_number"
        case cover
        case overview
        case airDate = "air_date"
        case episodeCount = "episode_count"
        case voteAverage = "vote_average"
    }
    
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        name = container?.decodeFlexibleStringIfPresent(forKey: .name)
        seasonNumber = container?.decodeFlexibleIntIfPresent(forKey: .seasonNumber)
        cover = container?.decodeFlexibleStringIfPresent(forKey: .cover)
        overview = container?.decodeFlexibleStringIfPresent(forKey: .overview)
        airDate = container?.decodeFlexibleStringIfPresent(forKey: .airDate)
        episodeCount = container?.decodeFlexibleIntIfPresent(forKey: .episodeCount)
        voteAverage = try? container?.decodeIfPresent(Double.self, forKey: .voteAverage)
    }
}

struct XtreamEpisode: Codable, Identifiable {
    let id: String? // "1234"
    let episodeNum: Int?
    let title: String?
    let containerExtension: String?
    let info: XtreamEpisodeInfo?
    
    enum CodingKeys: String, CodingKey {
        case id
        case episodeNum = "episode_num"
        case title
        case containerExtension = "container_extension"
        case info
    }
    
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        id = container?.decodeFlexibleStringIfPresent(forKey: .id)
        episodeNum = container?.decodeFlexibleIntIfPresent(forKey: .episodeNum)
        title = container?.decodeFlexibleStringIfPresent(forKey: .title)
        containerExtension = container?.decodeFlexibleStringIfPresent(forKey: .containerExtension)
        info = try? container?.decodeIfPresent(XtreamEpisodeInfo.self, forKey: .info)
    }
}

struct XtreamEpisodeInfo: Codable {
    let plot: String?
    let duration: String?
    let rating: String?
    let cover: String?
    let movieImage: String?
    
    enum CodingKeys: String, CodingKey {
        case plot, duration, rating, cover
        case movieImage = "movie_image"
    }
    
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        plot = container?.decodeFlexibleStringIfPresent(forKey: .plot)
        duration = container?.decodeFlexibleStringIfPresent(forKey: .duration)
        rating = container?.decodeFlexibleStringIfPresent(forKey: .rating)
        cover = container?.decodeFlexibleStringIfPresent(forKey: .cover)
        movieImage = container?.decodeFlexibleStringIfPresent(forKey: .movieImage)
    }
}
// MARK: - VOD Info
struct XtreamVODInfoResponse: Codable {
    let info: XtreamVODInfo?
    let movieData: XtreamVODMovieData?
    
    enum CodingKeys: String, CodingKey {
        case info
        case movieData = "movie_data"
    }
}

struct XtreamVODInfo: Codable {
    let name: String?
    let movieImage: String?
    let coverBig: String?
    let plot: String?
    let cast: String?
    let director: String?
    let genre: String?
    let releaseDate: String?
    let rating: String?
    let backdropPath: [String]?
    let youtubeTrailer: String?
    let duration: String?
    let durationSecs: Int?
    let tmdbId: String?
    let kinopoiskURL: String?
    
    enum CodingKeys: String, CodingKey {
        case name, plot, cast, director, genre, rating, duration
        case movieImage = "movie_image"
        case coverBig = "cover_big"
        case releaseDate = "releasedate"
        case backdropPath = "backdrop_path"
        case youtubeTrailer = "youtube_trailer"
        case durationSecs = "duration_secs"
        case tmdbId = "tmdb_id"
        case kinopoiskURL = "kinopoisk_url"
    }
    
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        name = container?.decodeFlexibleStringIfPresent(forKey: .name)
        movieImage = container?.decodeFlexibleStringIfPresent(forKey: .movieImage)
        coverBig = container?.decodeFlexibleStringIfPresent(forKey: .coverBig)
        plot = container?.decodeFlexibleStringIfPresent(forKey: .plot)
        cast = container?.decodeFlexibleStringIfPresent(forKey: .cast)
        director = container?.decodeFlexibleStringIfPresent(forKey: .director)
        genre = container?.decodeFlexibleStringIfPresent(forKey: .genre)
        releaseDate = container?.decodeFlexibleStringIfPresent(forKey: .releaseDate)
        rating = container?.decodeFlexibleStringIfPresent(forKey: .rating)
        backdropPath = try? container?.decodeIfPresent([String].self, forKey: .backdropPath)
        youtubeTrailer = container?.decodeFlexibleStringIfPresent(forKey: .youtubeTrailer)
        duration = container?.decodeFlexibleStringIfPresent(forKey: .duration)
        durationSecs = container?.decodeFlexibleIntIfPresent(forKey: .durationSecs)
        tmdbId = container?.decodeFlexibleStringIfPresent(forKey: .tmdbId)
        kinopoiskURL = container?.decodeFlexibleStringIfPresent(forKey: .kinopoiskURL)
    }
}

struct XtreamVODMovieData: Codable {
    let streamId: Int?
    let name: String?
    let added: String?
    let categoryId: String?
    let containerExtension: String?
    let customSid: String?
    let directSource: String?
    
    enum CodingKeys: String, CodingKey {
        case name, added
        case streamId = "stream_id"
        case categoryId = "category_id"
        case containerExtension = "container_extension"
        case customSid = "custom_sid"
        case directSource = "direct_source"
    }
    
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        streamId = container?.decodeFlexibleIntIfPresent(forKey: .streamId)
        name = container?.decodeFlexibleStringIfPresent(forKey: .name)
        added = container?.decodeFlexibleStringIfPresent(forKey: .added)
        categoryId = container?.decodeFlexibleStringIfPresent(forKey: .categoryId)
        containerExtension = container?.decodeFlexibleStringIfPresent(forKey: .containerExtension)
        customSid = container?.decodeFlexibleStringIfPresent(forKey: .customSid)
        directSource = container?.decodeFlexibleStringIfPresent(forKey: .directSource)
    }
}
