import Foundation

// MARK: - Parser output types

struct XMLTVChannel: Equatable, Sendable {
    let id: String                 // normalized channelKey
    let displayNames: [String]     // original case
    let iconURL: String?
}

struct XMLTVProgramme: Equatable, Sendable {
    let channelKey: String
    let startTs: Int64
    let stopTs: Int64
    let title: String
    let subtitle: String?
    let desc: String?
    let category: String?
    let iconURL: String?
    let episodeNum: String?
}

nonisolated struct XMLTVParseDiagnostics: Equatable, Sendable {
    var totalProgrammes = 0
    var matchedProgrammes = 0
    var skippedOutOfWindow = 0
    var matchedChannels = 0
    var malformedDates = 0
}

/// Streaming XMLTV parser (Foundation `XMLParser`, SAX). Meant to be run away
/// from the main thread. Channels/programmes are filtered to a wanted set
/// *during* parse so the ~98% of a large feed that a playlist doesn't reference
/// never allocates child text. Timestamps are parsed with byte arithmetic — no `DateFormatter`
/// per row (feeds routinely carry 100k–500k programmes).
///
/// `nonisolated` lifts the project's default `@MainActor` isolation, nothing
/// more: `parse` is synchronous and runs on the thread that calls it, callbacks
/// included. Keeping it off the main thread is the caller's job
/// (`EPGRefreshCoordinator.refresh` is `@concurrent` for that reason).
nonisolated final class EPGXMLTVParser: NSObject, XMLParserDelegate {

    struct Options: Sendable {
        var wantedChannelIds: Set<String>      // normalized
        var wantedDisplayNames: Set<String>    // normalized
        var pastCutoffTs: Int64
        var futureCutoffTs: Int64
        var defaultUTCOffsetSeconds: Int       // policy for offset-less datetimes
        var batchSize: Int = EPGConstants.parseBatchSize
    }

    private let options: Options
    private let onChannelBatch: ([XMLTVChannel]) -> Bool
    private let onProgrammeBatch: ([XMLTVProgramme]) -> Bool

    // Accumulated channel ids accepted via display-name fallback, so their
    // programmes match even though the id wasn't in the wanted set.
    private var acceptedIds: Set<String> = []

    private var channelBatch: [XMLTVChannel] = []
    private var programmeBatch: [XMLTVProgramme] = []
    private var diagnostics = XMLTVParseDiagnostics()
    private var aborted = false
    private weak var activeParser: XMLParser?

    // Current-element state.
    private enum Leaf { case none, displayName, title, subTitle, desc, category, episodeNum }
    private var leaf: Leaf = .none
    private var text = ""

    // Current <channel>.
    private var inChannel = false
    private var channelId: String?
    private var channelDisplayNames: [String] = []
    private var channelIcon: String?

    // Current <programme>.
    private var inProgramme = false
    private var skipProgramme = false
    private var progChannelKey = ""
    private var progStart: Int64 = 0
    private var progStop: Int64 = 0
    private var progTitle: String?
    private var progSubtitle: String?
    private var progDesc: String?
    private var progCategory: String?
    private var progIcon: String?
    private var progEpisodeNum: String?

    init(options: Options,
         onChannelBatch: @escaping ([XMLTVChannel]) -> Bool,
         onProgrammeBatch: @escaping ([XMLTVProgramme]) -> Bool) {
        self.options = options
        self.onChannelBatch = onChannelBatch
        self.onProgrammeBatch = onProgrammeBatch
    }

    // MARK: Entry points

    func parse(data: Data) throws -> XMLTVParseDiagnostics {
        let parser = XMLParser(data: data)
        return try run(parser)
    }

    func parse(fileURL: URL) throws -> XMLTVParseDiagnostics {
        guard let stream = InputStream(url: fileURL) else { throw EPGError.parse("stream") }
        let parser = XMLParser(stream: stream)
        return try run(parser)
    }

    private func run(_ parser: XMLParser) throws -> XMLTVParseDiagnostics {
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        activeParser = parser
        let ok = parser.parse()
        activeParser = nil
        // Flush any trailing partial batch (unless a callback already aborted).
        if !aborted {
            flushChannels()
            flushProgrammes()
        }
        if aborted { throw EPGError.cancelled }
        if !ok, let err = parser.parserError as NSError?, err.code != 512 /* userAborted */ {
            throw EPGError.parse(err.localizedDescription)
        }
        return diagnostics
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        switch elementName {
        case "channel":
            inChannel = true
            channelId = EPGConstants.normalizeChannelKey(attributeDict["id"])
            channelDisplayNames = []
            channelIcon = nil
            leaf = .none

        case "programme":
            diagnostics.totalProgrammes += 1
            inProgramme = true
            resetProgramme()
            let key = EPGConstants.normalizeChannelKey(attributeDict["channel"]) ?? ""
            progChannelKey = key
            // Fast reject: unmatched channel or out-of-window → don't accumulate text.
            guard options.wantedChannelIds.contains(key) || acceptedIds.contains(key) else {
                skipProgramme = true
                return
            }
            guard let start = Self.parseXMLTVTimestamp(attributeDict["start"], defaultOffsetSeconds: options.defaultUTCOffsetSeconds) else {
                diagnostics.malformedDates += 1
                skipProgramme = true
                return
            }
            // Missing/blank stop → assume a nominal 1h slot so the row is usable.
            let stop = Self.parseXMLTVTimestamp(attributeDict["stop"], defaultOffsetSeconds: options.defaultUTCOffsetSeconds) ?? (start + 3600)
            guard stop > options.pastCutoffTs, start < options.futureCutoffTs else {
                diagnostics.skippedOutOfWindow += 1
                skipProgramme = true
                return
            }
            progStart = start
            progStop = stop

        case "display-name" where inChannel:
            leaf = .displayName; text = ""
        case "title" where inProgramme && !skipProgramme:
            leaf = .title; text = ""
        case "sub-title" where inProgramme && !skipProgramme:
            leaf = .subTitle; text = ""
        case "desc" where inProgramme && !skipProgramme:
            leaf = .desc; text = ""
        case "category" where inProgramme && !skipProgramme:
            leaf = .category; text = ""
        case "episode-num" where inProgramme && !skipProgramme:
            leaf = .episodeNum; text = ""
        case "icon":
            if let src = attributeDict["src"], !src.isEmpty {
                if inProgramme, !skipProgramme, progIcon == nil { progIcon = src }
                else if inChannel, channelIcon == nil { channelIcon = src }
            }
            leaf = .none
        default:
            leaf = .none
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard leaf != .none else { return }
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard leaf != .none, let s = String(data: CDATABlock, encoding: .utf8) else { return }
        text += s
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "channel":
            finishChannel()
            inChannel = false
            leaf = .none

        case "programme":
            finishProgramme()
            inProgramme = false
            skipProgramme = false
            leaf = .none

        case "display-name":
            let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { channelDisplayNames.append(v) }
            leaf = .none
        case "title":     progTitle = trimmedOrNil();    leaf = .none
        case "sub-title": progSubtitle = trimmedOrNil(); leaf = .none
        case "desc":      progDesc = trimmedOrNil();     leaf = .none
        case "category":  if progCategory == nil { progCategory = trimmedOrNil() }; leaf = .none
        case "episode-num": if progEpisodeNum == nil { progEpisodeNum = trimmedOrNil() }; leaf = .none
        default:
            leaf = .none
        }
    }

    // MARK: Assembly

    private func trimmedOrNil() -> String? {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private func resetProgramme() {
        skipProgramme = false
        progTitle = nil; progSubtitle = nil; progDesc = nil
        progCategory = nil; progIcon = nil; progEpisodeNum = nil
        progStart = 0; progStop = 0
    }

    private func finishChannel() {
        guard let id = channelId else { return }
        let matchesId = options.wantedChannelIds.contains(id)
        let matchesName = channelDisplayNames.contains { options.wantedDisplayNames.contains($0.lowercased()) }
        guard matchesId || matchesName else { return }
        if matchesName { acceptedIds.insert(id) }
        diagnostics.matchedChannels += 1
        channelBatch.append(XMLTVChannel(id: id, displayNames: channelDisplayNames, iconURL: channelIcon))
        if channelBatch.count >= options.batchSize { flushChannels() }
    }

    private func finishProgramme() {
        guard inProgramme, !skipProgramme else { return }
        diagnostics.matchedProgrammes += 1
        programmeBatch.append(XMLTVProgramme(
            channelKey: progChannelKey,
            startTs: progStart, stopTs: progStop,
            title: progTitle ?? "",
            subtitle: progSubtitle, desc: progDesc,
            category: progCategory, iconURL: progIcon, episodeNum: progEpisodeNum
        ))
        if programmeBatch.count >= options.batchSize { flushProgrammes() }
    }

    private func flushChannels() {
        guard !channelBatch.isEmpty else { return }
        let batch = channelBatch
        channelBatch.removeAll(keepingCapacity: true)
        if !onChannelBatch(batch) { aborted = true; activeParser?.abortParsing() }
    }

    private func flushProgrammes() {
        guard !programmeBatch.isEmpty else { return }
        let batch = programmeBatch
        programmeBatch.removeAll(keepingCapacity: true)
        if !onProgrammeBatch(batch) { aborted = true; activeParser?.abortParsing() }
    }

    // MARK: Timestamp parsing

    /// Parses an XMLTV datetime ("YYYYMMDDHHMMSS ±HHMM", tolerating truncation to
    /// YYYYMMDDHHMM and a missing offset) into unix epoch seconds (UTC). Offset-less
    /// values are interpreted with `defaultOffsetSeconds` (the feed's assumed zone).
    static func parseXMLTVTimestamp(_ raw: String?, defaultOffsetSeconds: Int) -> Int64? {
        guard let raw else { return nil }
        // Split digits (datetime) from an optional trailing signed offset.
        let bytes = Array(raw.utf8)
        var digits: [Int] = []
        digits.reserveCapacity(14)
        var offsetSeconds = defaultOffsetSeconds
        var i = 0
        // Leading whitespace.
        while i < bytes.count, bytes[i] == 0x20 { i += 1 }
        while i < bytes.count {
            let b = bytes[i]
            if b >= 0x30 && b <= 0x39 {
                if digits.count < 14 { digits.append(Int(b - 0x30)) }
                i += 1
            } else if b == 0x20 || b == 0x2B || b == 0x2D {
                break   // start of the offset field
            } else {
                i += 1  // tolerate stray separators inside the datetime
            }
        }
        // Parse optional offset: [space] (+|-) HHMM
        while i < bytes.count, bytes[i] == 0x20 { i += 1 }
        if i < bytes.count, bytes[i] == 0x2B || bytes[i] == 0x2D {
            let sign = bytes[i] == 0x2D ? -1 : 1
            i += 1
            var offDigits: [Int] = []
            while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 { offDigits.append(Int(bytes[i] - 0x30)); i += 1 }
            if offDigits.count >= 4 {
                let oh = offDigits[0] * 10 + offDigits[1]
                let om = offDigits[2] * 10 + offDigits[3]
                offsetSeconds = sign * (oh * 3600 + om * 60)
            } else if offDigits.count >= 2 {
                let oh = offDigits[0] * 10 + offDigits[1]
                offsetSeconds = sign * (oh * 3600)
            }
        }

        guard digits.count >= 12 else { return nil }   // need at least YYYYMMDDHHMM
        func num(_ start: Int, _ len: Int) -> Int {
            var v = 0
            for k in start..<(start + len) { v = v * 10 + digits[k] }
            return v
        }
        let year = num(0, 4)
        let month = num(4, 2)
        let day = num(6, 2)
        let hour = num(8, 2)
        let minute = num(10, 2)
        let second = digits.count >= 14 ? num(12, 2) : 0
        guard month >= 1, month <= 12, day >= 1, day <= 31, hour < 24, minute < 60, second < 60 else { return nil }

        let days = daysFromCivil(year: year, month: month, day: day)
        let epoch = Int64(days) * 86_400 + Int64(hour) * 3600 + Int64(minute) * 60 + Int64(second) - Int64(offsetSeconds)
        return epoch
    }

    /// Howard Hinnant's `days_from_civil`: days since 1970-01-01 for a proleptic
    /// Gregorian date. Avoids Calendar/DateComponents overhead.
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
