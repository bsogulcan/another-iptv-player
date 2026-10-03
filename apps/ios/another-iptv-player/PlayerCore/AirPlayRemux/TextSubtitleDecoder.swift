import Foundation
import Libavcodec
import Libavformat
import Libavutil

/// Decode the selected text stream on the existing remux connection. Bitmap
/// subtitles need video compositing and cannot be represented as WebVTT.
final class TextSubtitleDecoder {
  private var context: UnsafeMutablePointer<AVCodecContext>?

  init?(stream: UnsafeMutablePointer<AVStream>) {
    guard let parameters = stream.pointee.codecpar,
          Self.textCodecs.contains(parameters.pointee.codec_id.rawValue),
          let codec = avcodec_find_decoder(parameters.pointee.codec_id)
    else { return nil }
    context = avcodec_alloc_context3(codec)
    guard let context else { return nil }
    guard avcodec_parameters_to_context(context, parameters) >= 0 else { return nil }
    context.pointee.pkt_timebase = stream.pointee.time_base
    guard avcodec_open2(context, codec, nil) >= 0 else { return nil }
  }

  static let textCodecs: Set<UInt32> = [
    AV_CODEC_ID_SUBRIP.rawValue, AV_CODEC_ID_ASS.rawValue, AV_CODEC_ID_SSA.rawValue,
    AV_CODEC_ID_MOV_TEXT.rawValue, AV_CODEC_ID_WEBVTT.rawValue, AV_CODEC_ID_TEXT.rawValue,
  ]

  func decode(packet: inout AVPacket, timeBase: AVRational, inputStartTime: Int64) -> [SubtitleEntry] {
    guard let context else { return [] }
    let pts = packet.pts == Int64.min ? packet.dts : packet.pts
    guard pts != Int64.min else { return [] }
    var subtitle = AVSubtitle()
    defer { avsubtitle_free(&subtitle) }
    var gotSubtitle: Int32 = 0
    guard avcodec_decode_subtitle2(context, &subtitle, &gotSubtitle, &packet) >= 0,
          gotSubtitle != 0 else { return [] }
    let start = RemuxHLSWriter.contentSeconds(
      containerSeconds: Double(pts) * av_q2d(timeBase), inputStartTime: inputStartTime
    ) + Double(subtitle.start_display_time) / 1000
    let displayDuration = subtitle.end_display_time == UInt32.max ? 0
      : Double(subtitle.end_display_time) / 1000 - Double(subtitle.start_display_time) / 1000
    let duration = displayDuration > 0 ? displayDuration : Double(packet.duration) * av_q2d(timeBase)
    let end = start + (duration > 0 ? duration : 3)
    var texts: [String] = []
    for index in 0..<Int(subtitle.num_rects) {
      guard let rect = subtitle.rects[index] else { continue }
      if let text = rect.pointee.text {
        texts.append(String(cString: text))
      } else if let ass = rect.pointee.ass {
        // FFmpeg's ASS event has eight comma-separated fields before the text;
        // commas in the dialogue itself must be retained.
        let fields = String(cString: ass).split(separator: ",", maxSplits: 8, omittingEmptySubsequences: false)
        if fields.count == 9 { texts.append(Self.plainText(fromASS: String(fields[8]))) }
      }
    }
    let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return [] }
    return [SubtitleEntry(startTime: start, endTime: end, text: text)]
  }

  static func plainText(fromASS text: String) -> String {
    SRTParser.strippingMarkupTags(SRTParser.strippingOverrideBlocks(text))
      .replacingOccurrences(of: "\\N", with: "\n")
      .replacingOccurrences(of: "\\n", with: "\n")
      .replacingOccurrences(of: "\\h", with: " ")
  }

  deinit { avcodec_free_context(&context) }
}
