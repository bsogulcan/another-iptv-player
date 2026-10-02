import Foundation

/// Builds the HLS WebVTT subtitle rendition served alongside the remuxed video so
/// subtitles show on the AirPlay target. The remuxed TS video segments carry absolute
/// source PTS, and WebVTT cues are emitted in verbatim source (SRT) time with
/// `X-TIMESTAMP-MAP:MPEGTS:0` — so cue N lines up with the video frame at source-time N
/// whether the cast started from 0:00 or from a resume position (both are absolute
/// source time). If a panel's muxer applied a constant PTS offset, only `mpegtsClock`
/// needs tuning — the cue times stay put.
///
/// The writer adds one constant base to every TS timestamp
/// (`RemuxHLSWriter.tsTimestampBase90k`) and passes that same value as `mpegtsClock`,
/// so the map reads `MPEGTS:<base>` rather than `MPEGTS:0`; without it every cue would
/// show that base early.
///
/// Phase 1 covers text subtitles (external SRT) over the H.264/MPEG-TS remux path.
/// HEVC/fMP4 and bitmap (PGS/DVB) subtitles are out of scope here.
enum AirPlaySubtitleRendition {
  static let videoGroupID = "subs"

  /// Parsed cues + the WebVTT document + the span the cues cover. `nil` when the file
  /// can't be read or has no usable cues.
  struct Built {
    let webVTT: String
    let durationSeconds: Double
  }

  /// Reads an SRT file and returns the WebVTT document. Returns nil for an unreadable
  /// or empty file (caller then skips the rendition and casts video-only).
  static func build(fromSRTFile url: URL, mpegtsClock: Int64 = 0) -> Built? {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    let entries = SRTParser().parse(content: content)
    guard !entries.isEmpty else { return nil }
    return build(from: entries, mpegtsClock: mpegtsClock)
  }

  static func build(from entries: [SubtitleEntry], mpegtsClock: Int64 = 0) -> Built {
    var out = "WEBVTT\n"
    out += "X-TIMESTAMP-MAP=MPEGTS:\(mpegtsClock),LOCAL:00:00:00.000\n\n"
    var maxEnd: Double = 0
    for entry in entries {
      let start = max(entry.startTime, 0)
      let end = max(entry.endTime, start + 0.1)
      maxEnd = max(maxEnd, end)
      // A stray "-->" inside cue text would break WebVTT parsing; harmless to neutralise.
      let text = entry.text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "-->", with: "->")
      out += "\(timestamp(start)) --> \(timestamp(end))\n\(text)\n\n"
    }
    return Built(webVTT: out, durationSeconds: maxEnd)
  }

  /// Subtitle media playlist: one WebVTT "segment" spanning the whole VOD.
  static func subtitleMediaPlaylist(vttFileName: String, durationSeconds: Double) -> String {
    let dur = max(durationSeconds, 1)
    return [
      "#EXTM3U",
      "#EXT-X-VERSION:3",
      "#EXT-X-TARGETDURATION:\(Int(dur.rounded(.up)))",
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-PLAYLIST-TYPE:VOD",
      String(format: "#EXTINF:%.3f,", dur),
      vttFileName,
      "#EXT-X-ENDLIST",
      "",
    ].joined(separator: "\n")
  }

  /// Master playlist referencing the (unchanged) video media playlist + the subtitle group.
  /// Handed to the cast AVPlayer instead of the raw video playlist when a subtitle exists.
  static func masterPlaylist(
    videoPlaylistFileName: String,
    subtitlePlaylistFileName: String,
    name: String,
    languageCode: String?
  ) -> String {
    var mediaLine =
      "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"\(videoGroupID)\",NAME=\"\(sanitize(name))\","
    mediaLine += "DEFAULT=YES,AUTOSELECT=YES,FORCED=NO,"
    if let lang = languageCode, !lang.isEmpty {
      mediaLine += "LANGUAGE=\"\(sanitize(lang))\","
    }
    mediaLine += "URI=\"\(subtitlePlaylistFileName)\""
    return [
      "#EXTM3U",
      "#EXT-X-VERSION:3",
      "#EXT-X-INDEPENDENT-SEGMENTS",
      mediaLine,
      "#EXT-X-STREAM-INF:BANDWIDTH=6000000,SUBTITLES=\"\(videoGroupID)\"",
      videoPlaylistFileName,
      "",
    ].joined(separator: "\n")
  }

  // MARK: - Helpers

  private static func timestamp(_ seconds: TimeInterval) -> String {
    let ms = Int((max(seconds, 0) * 1000).rounded())
    let h = ms / 3_600_000
    let m = (ms % 3_600_000) / 60_000
    let s = (ms % 60_000) / 1000
    let milli = ms % 1000
    return String(format: "%02d:%02d:%02d.%03d", h, m, s, milli)
  }

  /// Strip characters that would break the m3u8 attribute quoting.
  private static func sanitize(_ value: String) -> String {
    value.replacingOccurrences(of: "\"", with: "")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: ",", with: " ")
  }
}
