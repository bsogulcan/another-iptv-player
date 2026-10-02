import Foundation
import GRDB

// Guide data of the rich mode, shared by its Xtream and its M3U playlist.
// Programme times are generated around the seed time: a guide with fixed dates
// would lie in the past on the day a test runs, and nothing would be on air.
extension MockFixture {

    /// One channel of a seeded guide.
    struct GuideChannel {
        /// Stored channel key, see `guideKey(_:)`.
        var key: String
        var displayName: String
        var iconURL: String?
        /// Programme lengths in minutes, repeated until the window is full.
        var pattern: [Int]
        var titles: [String]
        var category: String?
        /// Also gets a day-long entry lying under its real programmes, the way
        /// feeds pad a channel they have no schedule for. The on-air lookup has
        /// to prefer the real programme; the guide grid meets both.
        var hasDayPlaceholder = false
    }

    static let guidePlaceholderTitle = "To Be Announced"

    /// The form guide rows are keyed by: trimmed and lowercased, which is how the
    /// guide import stores an XMLTV channel id and how channels look theirs up.
    static func guideKey(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// From local midnight of the seed day minus 12 h to plus 36 h: yesterday
    /// afternoon (past programmes, for the archive), today, tomorrow morning.
    static func guideWindow(around now: Date, calendar: Calendar = .current) -> DateInterval {
        let midnight = calendar.startOfDay(for: now)
        return DateInterval(start: midnight.addingTimeInterval(-12 * 3_600),
                            end: midnight.addingTimeInterval(36 * 3_600))
    }

    /// Writes the channel rows, back-to-back programmes over `guideWindow` and the
    /// bookkeeping row that marks the guide as refreshed at `now`, so the app sees
    /// a fresh guide and starts no download. Returns the number of programmes.
    @discardableResult
    static func insertGuide(db: Database, playlistId: UUID, sourceType: EPGSourceType, sourceURL: String?,
                            channels: [GuideChannel], now: Date, calendar: Calendar = .current) throws -> Int {
        let window = guideWindow(around: now, calendar: calendar)
        let dayStart = calendar.startOfDay(for: now)
        var programmeCount = 0

        for channel in channels {
            try DBEPGChannel(
                playlistId: playlistId,
                channelKey: channel.key,
                displayName: channel.displayName,
                iconURL: channel.iconURL
            ).insert(db)

            var start = window.start
            var index = 0
            while start < window.end, !channel.pattern.isEmpty {
                let minutes = channel.pattern[index % channel.pattern.count]
                let stop = min(start.addingTimeInterval(TimeInterval(minutes * 60)), window.end)
                // A channel cannot hold two programmes with the same start (it is
                // part of the row's key), so the placeholder takes this slot alone.
                if !(channel.hasDayPlaceholder && start == dayStart) {
                    try programme(index, of: channel, playlistId: playlistId, start: start, stop: stop).insert(db)
                    programmeCount += 1
                }
                start = stop
                index += 1
            }

            if channel.hasDayPlaceholder {
                try DBEPGProgramme(
                    playlistId: playlistId,
                    channelKey: channel.key,
                    startTs: Int64(dayStart.timeIntervalSince1970),
                    stopTs: Int64(dayStart.addingTimeInterval(24 * 3_600).timeIntervalSince1970),
                    title: guidePlaceholderTitle
                ).insert(db)
                programmeCount += 1
            }
        }

        try stampGuideSource(db: db, playlistId: playlistId, sourceType: sourceType, url: sourceURL,
                             now: now, programmeCount: programmeCount, channelCount: channels.count)
        return programmeCount
    }

    private static func programme(_ index: Int, of channel: GuideChannel, playlistId: UUID,
                                  start: Date, stop: Date) -> DBEPGProgramme {
        let title = channel.titles.isEmpty ? channel.displayName : channel.titles[index % channel.titles.count]
        // Every fourth description is long enough to need the programme sheet's
        // "more" control; a third of the programmes are episodes of something.
        let desc = index % 4 == 0
            ? "\(title) on \(channel.displayName). A longer placeholder description for demo purposes: who is in it, what it is about and why it is worth staying for, spread over enough sentences to wrap several times on a phone."
            : "\(title) on \(channel.displayName). A placeholder description for demo purposes."
        let isEpisode = index % 3 == 1
        return DBEPGProgramme(
            playlistId: playlistId,
            channelKey: channel.key,
            startTs: Int64(start.timeIntervalSince1970),
            stopTs: Int64(stop.timeIntervalSince1970),
            title: title,
            subtitle: isEpisode ? "Part \(index % 6 + 1)" : nil,
            desc: desc,
            category: channel.category,
            iconURL: nil,
            episodeNum: isEpisode ? "S1E\(index % 6 + 1)" : nil
        )
    }

    // MARK: - Programme shapes

    /// Schedules by kind of channel. Lengths are 15, 30 and 120 minutes, in
    /// patterns that divide the 48 h window so no programme is cut short.
    enum GuideShape {
        case news, business, sport, events, film, music, comedy, documentary, kids

        var pattern: [Int] {
            switch self {
            case .news:        return [30, 15, 15, 30, 30]
            case .business:    return [30, 30, 15, 15, 30]
            case .sport:       return [120]
            case .events:      return [120, 120, 30, 30, 30, 30]
            case .film:        return [120]
            case .music:       return [30, 30, 15, 15]
            case .comedy:      return [30]
            case .documentary: return [30, 30, 120]
            case .kids:        return [15]
            }
        }

        var category: String {
            switch self {
            case .news:        return "News"
            case .business:    return "Business"
            case .sport:       return "Sports"
            case .events:      return "Sports"
            case .film:        return "Movie"
            case .music:       return "Music"
            case .comedy:      return "Comedy"
            case .documentary: return "Documentary"
            case .kids:        return "Children"
            }
        }

        var titles: [String] {
            switch self {
            case .news:
                return ["Morning Headlines", "World Report", "Weather Update", "The Briefing",
                        "Breaking: Special Extended Coverage of the International Summit",
                        "Global Desk", "Press Review", "Evening News", "Newsnight", "In Depth"]
            case .business:
                return ["Opening Bell", "Money Matters", "Market Watch", "Startup Stories",
                        "The Ledger", "Trade Winds", "Closing Bell"]
            case .sport:
                return ["Matchday Live", "The Final Whistle", "Sports Tonight", "Highlights Hour", "Championship Replay"]
            case .events:
                return ["Centre Court Live", "Quarter-Final Replay", "Baseline", "Open Review", "Legends Match", "Court Report"]
            case .film:
                return ["Afternoon Feature", "Double Bill", "Premiere Night", "Late Night Cinema", "Directors' Cut"]
            case .music:
                return ["Top 20 Countdown", "Acoustic Sessions", "Throwback Hits", "New Releases", "Live Lounge"]
            case .comedy:
                return ["Stand-Up Hour", "Sketch Night", "The Late Laugh", "Open Mic", "Roast Room"]
            case .documentary:
                return ["Wild Planet", "How It Began", "Ocean Depths", "Built to Last", "Frontiers", "The Long Road North"]
            case .kids:
                return ["Tiny Explorers", "Robo Pals", "Storytime", "The Puzzle Club", "Animal Friends", "Sing Along", "Colour Lab"]
            }
        }
    }

    static func guideChannel(key: String, displayName: String, iconURL: String?, shape: GuideShape,
                             hasDayPlaceholder: Bool = false) -> GuideChannel {
        GuideChannel(key: key, displayName: displayName, iconURL: iconURL, pattern: shape.pattern,
                     titles: shape.titles, category: shape.category, hasDayPlaceholder: hasDayPlaceholder)
    }
}
