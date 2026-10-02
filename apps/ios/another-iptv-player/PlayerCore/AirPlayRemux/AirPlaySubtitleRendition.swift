import Foundation

/// Builds the HLS WebVTT subtitle rendition served alongside the remuxed video so
/// subtitles show on the AirPlay target. Cue times are relative to the source's
/// start time. Each segment's timestamp map pairs its content time with the media
/// clock: absolute PTS plus the base on TS, or PTS relative to the first DTS on fMP4.
///
/// Text subtitles use the video's timestamp origin on TS and fMP4. Bitmap
/// (PGS/DVB) subtitles need compositing and are not representable as WebVTT.
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

  static func build(from entries: [SubtitleEntry], mpegtsClock: Int64 = 0, localSeconds: Double = 0) -> Built {
    var out = "WEBVTT\n"
    out += "X-TIMESTAMP-MAP=MPEGTS:\(mpegtsClock),LOCAL:\(timestamp(localSeconds))\n\n"
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
    languageCode: String?,
    bandwidth: Int = 6_000_000,
    version: Int = 3
  ) -> String {
    var mediaLine =
      "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"\(videoGroupID)\",NAME=\"\(sanitize(name))\","
    mediaLine += "DEFAULT=YES,AUTOSELECT=YES,FORCED=NO,"
    // Container tags commonly use ISO 639-2 ("tur"); HLS uses BCP 47 ("tr").
    // Keep region/script subtags, and include "und" for an unknown language.
    let parts = (languageCode ?? "und").replacingOccurrences(of: "_", with: "-")
      .split(separator: "-").map(String.init)
    let base = parts.first ?? "und"
    let language = ([PlaybackTrackPreferences.twoLetterCode(for: base) ?? base]
      + parts.dropFirst()).joined(separator: "-")
    mediaLine += "LANGUAGE=\"\(sanitize(language))\","
    mediaLine += "URI=\"\(subtitlePlaylistFileName)\""
    return [
      "#EXTM3U",
      "#EXT-X-VERSION:\(version)",
      "#EXT-X-INDEPENDENT-SEGMENTS",
      mediaLine,
      "#EXT-X-STREAM-INF:BANDWIDTH=\(bandwidth),SUBTITLES=\"\(videoGroupID)\"",
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
