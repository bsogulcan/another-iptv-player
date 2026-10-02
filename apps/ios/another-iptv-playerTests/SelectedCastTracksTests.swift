import AVFoundation
import Foundation
import Libavcodec
import Libavformat
import Libavutil
import Testing
import UIKit
@testable import another_iptv_player

private final class CastTracksFixtureBundle: NSObject {}

@MainActor
private final class CastSubtitleCollector: NSObject, @preconcurrency AVPlayerItemLegibleOutputPushDelegate {
  var text = ""
  var secondCueTime: Double?

  func legibleOutput(
    _ output: AVPlayerItemLegibleOutput, didOutputAttributedStrings strings: [NSAttributedString],
    nativeSampleBuffers: [Any], forItemTime itemTime: CMTime
  ) {
    text += strings.map(\.string).joined(separator: "\n")
    if strings.contains(where: { $0.string.contains("İkinci satır") }) {
      secondCueTime = itemTime.seconds
    }
  }
}

@Suite("SelectedCastTracks")
struct SelectedCastTracksTests {
  /// Reproduce a return from AirPlay after a non-keyframe resume. Keeping the
  /// item avoids another provider open and the second loading cycle.
  @Test(arguments: [false, true], [false, true]) @MainActor
  func phoneContinuationKeepsPreparedPlayerAndResumePosition(paused: Bool, loseLocalVideo: Bool) async throws {
    let source = try #require(Bundle(for: CastTracksFixtureBundle.self)
      .url(forResource: "selected-tracks-growing", withExtension: "mkv"))
    let controller = CastController()
    defer { controller.dispose() }
    var engineStops = 0
    var engineResumes = 0
    var ticks: [TimeInterval] = []
    controller.attachOwner(
      token: UUID(), stopDirectPlayback: { engineStops += 1 },
      resumeDirectPlayback: { _, _ in engineResumes += 1 }, onTimeTick: { ticks.append($0) }
    )
    let content = CastController.Content(
      url: source, isLive: false, userAgent: nil, startAt: 5.5,
      knownDuration: 36, nativelyPlayable: false, startPaused: paused,
      subtitleName: "Türkçe", subtitleLanguage: "tur",
      audioStreamIndex: 2, subtitleStreamIndex: 3
    )
    try #require(controller.startRemuxCast(content: content) { _ in })
    for _ in 0..<200 {
      if controller.isPlaybackEstablished { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    try #require(controller.isPlaybackEstablished)
    let view = try #require(controller.castVideoView as? AirPlayCastPlayer.View)
    let player = try #require(view.playerLayer.player)
    let item = try #require(player.currentItem)
    // The input seek goes backwards to the preceding keyframe. Playback must
    // skip that preroll rather than reporting 5.5 while replaying an earlier scene.
    for _ in 0..<50 {
      if controller.position >= 5.4, controller.isPaused == paused { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    #expect(controller.position >= 5.4)
    #expect(ticks.allSatisfy { $0 >= 5.4 }, "keyframe preroll must not be played or reported")
    let before = controller.position
    let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIViewController()
    window.isHidden = false
    defer { window.isHidden = true }
    let host = KSPlayerVideoContainerUIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
    window.rootViewController?.view.addSubview(host)
    host.attachIfNeeded(view)
    // Model an external renderer releasing its local layer association.
    view.playerLayer.player = nil
    try #require(controller.continuePlaybackLocally())
    let returnedView = try #require(controller.castVideoView as? AirPlayCastPlayer.View)
    #expect(returnedView !== view)
    host.attachIfNeeded(returnedView)
    host.layoutIfNeeded()
    if loseLocalVideo {
      // The item remains ready and can emit audio, but no layer receives video.
      returnedView.playerLayer.player = nil
      for _ in 0..<80 {
        if engineResumes > 0 { break }
        try await Task.sleep(for: .milliseconds(100))
      }
      #expect(engineResumes == 1, "a ready item without a visible frame must fall back")
      #expect(!controller.isEngaged)
      #expect(player.currentItem == nil)
      return
    }
    #expect(controller.isContinuingLocally)
    #expect(controller.isPresenting)
    #expect(!controller.hasRouteToPreserve)
    #expect(!controller.isPreparing)
    #expect(controller.isPlaybackEstablished)
    controller.pickerWillOpen()
    controller.pickerDidClose() // Cancelling a new picker must retain phone playback.
    controller.setLocalPlaybackSpeed(1.5)
    try await Task.sleep(for: .seconds(2))
    #expect(returnedView.playerLayer.player === player)
    #expect(returnedView.playerLayer.isReadyForDisplay, "the phone must display a frame, not only play audio")
    #expect(player.currentItem === item)
    #expect(engineStops == 1)
    #expect(engineResumes == 0)
    #expect(controller.isPaused == paused)
    if paused {
      #expect(abs(controller.position - before) < 0.3)
      controller.play()
      try await Task.sleep(for: .milliseconds(500))
    } else {
      #expect(controller.position > before + 1)
    }
    #expect(abs(player.rate - 1.5) < 0.01)
    controller.dispose()
    #expect(!controller.isEngaged)
    #expect(player.currentItem == nil)
    #expect(engineResumes == 0)
  }

  @Test @MainActor
  func phoneTrackSelectionsReachTheRunningRemux() async throws {
    let source = try #require(Bundle(for: CastTracksFixtureBundle.self)
      .url(forResource: "selected-tracks-growing", withExtension: "mkv"))
    let preferencesKey = "playback.trackPreferences.v1"
    let savedPreferences = UserDefaults.standard.object(forKey: preferencesKey)
    let owner = VideoPlayerController()
    defer {
      owner.teardown()
      UserDefaults.standard.set(savedPreferences, forKey: preferencesKey)
    }
    owner.play(url: source, startSeconds: 5.5)
    for _ in 0..<100 {
      if owner.needsAirPlayPreparation, owner.audioTracks.count == 2,
         owner.subtitleTracks.contains(where: { $0.id >= 0 }) { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    try #require(owner.needsAirPlayPreparation)
    owner.pause()
    let sourceAudioTracks = owner.audioTracks
    let sourceSubtitleTracks = owner.subtitleTracks
    let selectedSubtitle = try #require(sourceSubtitleTracks.first { $0.id >= 0 })
    let selectedAudio = try #require(sourceAudioTracks.first { $0.id != owner.currentAudioTrackId })
    var prepared: Bool?
    owner.prepareAirPlay { prepared = $0 }
    for _ in 0..<150 {
      if prepared != nil { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    try #require(prepared == true)
    let cast = try #require(owner.castController)
    let view = try #require(cast.castVideoView as? AirPlayCastPlayer.View)
    let player = try #require(view.playerLayer.player)
    #expect(owner.engine.layer == nil)
    #expect(owner.canSelectPlaybackTracks)
    #expect(owner.audioTracks == sourceAudioTracks)
    #expect(owner.subtitleTracks == sourceSubtitleTracks)

    func replacement(after previous: AVPlayerItem?) async throws -> AVPlayerItem {
      for _ in 0..<150 {
        if let item = player.currentItem, item !== previous, item.status == .readyToPlay { return item }
        try await Task.sleep(for: .milliseconds(100))
      }
      throw NSError(domain: "CastTrackTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "track selection did not replace the item"])
    }

    let beforeAudio = player.currentItem
    owner.selectAudioTrack(id: selectedAudio.id)
    let audioItem = try await replacement(after: beforeAudio)
    let audioURL = try #require((audioItem.asset as? AVURLAsset)?.url)
    let sessionDirectory = LocalHTTPServer.shared.directory
      .appendingPathComponent(audioURL.deletingLastPathComponent().lastPathComponent)
    // Inspect the emitted segment itself: AVURLAsset does not expose HLS audio
    // tracks consistently, even when the AVPlayerItem is ready and audible.
    #expect(try audioSampleRate(in: sessionDirectory.appendingPathComponent("seg00000.ts"))
      == (selectedAudio.id == 1 ? 32_000 : 48_000))
    #expect(owner.currentAudioTrackId == selectedAudio.id)

    owner.selectSubtitleTrack(id: selectedSubtitle.id)
    let subtitleItem = try await replacement(after: audioItem)
    let subtitleURL = try #require((subtitleItem.asset as? AVURLAsset)?.url)
    let (withSubtitles, _) = try await URLSession.shared.data(from: subtitleURL)
    #expect(String(decoding: withSubtitles, as: UTF8.self).contains("TYPE=SUBTITLES"))
    #expect(owner.currentSubtitleTrackId == selectedSubtitle.id)

    owner.selectSubtitleTrack(id: -1)
    let noSubtitleItem = try await replacement(after: subtitleItem)
    let noSubtitleURL = try #require((noSubtitleItem.asset as? AVURLAsset)?.url)
    let (withoutSubtitles, _) = try await URLSession.shared.data(from: noSubtitleURL)
    #expect(!String(decoding: withoutSubtitles, as: UTF8.self).contains("TYPE=SUBTITLES"))
    #expect(owner.currentSubtitleTrackId == -1)
    #expect(view.playerLayer.player === player)
    #expect(owner.engine.layer == nil)
    #expect(owner.canSelectPlaybackTracks)
  }

  @Test(arguments: ["selected-tracks", "selected-tracks-bframes", "selected-tracks-subrip"], [false, true]) @MainActor
  func avPlayerActuallyDecodesSelectedSubtitles(fixture: String, fmp4: Bool) async throws {
    try await checkAVPlayerSubtitles(fixture: fixture, fmp4: fmp4)
  }

  /// HEVC + E-AC-3 + SubRip, with source PTS ten minutes in. This reproduces
  /// the Mac receiver failure that short H.264 fixtures did not expose.
  @Test @MainActor
  func hevcSubtitlesUseTheFragmentClockAtResume() async throws {
    try await checkAVPlayerSubtitles(fixture: "selected-tracks-hevc", fmp4: true)
  }

  @Test(arguments: [false, true]) @MainActor
  func captionsArriveAfterInitiallyEmptyGrowingSegments(fmp4: Bool) async throws {
    try await checkAVPlayerSubtitles(fixture: "selected-tracks-growing", fmp4: fmp4, growing: true)
  }

  @MainActor
  private func checkAVPlayerSubtitles(fixture: String, fmp4: Bool, growing: Bool = false) async throws {
    let source = try #require(Bundle(for: CastTracksFixtureBundle.self)
      .url(forResource: fixture, withExtension: "mkv"))
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("cast-render-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let writer = RemuxHLSWriter(
      sourceURL: source, outputDirectory: directory, startSeconds: growing ? 0 : 4,
      isLive: false, userAgent: nil, forcedFormat: fmp4 ? .fmp4 : .mpegTS,
      subtitleName: "Türkçe", subtitleLanguage: "tur",
      audioStreamIndex: 2, subtitleStreamIndex: growing ? 3 : 4
    )
    let server = LocalHTTPServer(directory: directory)
    let castPlayer = AirPlayCastPlayer()
    defer {
      castPlayer.unload()
      server.stop()
      writer.cancel()
      if writer.isClosed { try? FileManager.default.removeItem(at: directory) }
    }
    writer.start()
    for _ in 0..<100 {
      if growing {
        if (try? String(contentsOf: writer.playlistURL, encoding: .utf8))?.contains("seg00005") == true { break }
      } else if writer.isClosed { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    if growing {
      try #require(!writer.isClosed)
      let initial = try String(contentsOf: directory.appendingPathComponent("subs00000.vtt"), encoding: .utf8)
      #expect(!initial.contains("-->"), "initial subtitles must really be empty")
    } else {
      try #require(writer.isClosed)
    }
    try server.start()
    let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/master.m3u8"))
    castPlayer.load(url: url, startAt: nil, autoPlay: false, preferredLegible: true)
    let player = try #require(castPlayer.view.playerLayer.player)
    let item = try #require(player.currentItem)
    let collector = CastSubtitleCollector()
    let output = AVPlayerItemLegibleOutput()
    output.setDelegate(collector, queue: .main)
    item.add(output)
    for _ in 0..<100 {
      if item.status != .unknown { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    try #require(item.status == .readyToPlay, "HLS load failed: \(String(describing: item.error))")
    let group = try #require(try await item.asset.loadMediaSelectionGroup(for: .legible))
    for _ in 0..<50 {
      if item.currentMediaSelection.selectedMediaOption(in: group) != nil { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    try #require(item.currentMediaSelection.selectedMediaOption(in: group) != nil)
    castPlayer.onTime = { writer.updatePlaybackPosition($0) }
    // Advance beyond the initial 25 s buffer while the writer publishes new
    // segments. Double speed keeps this regression test short.
    if growing { player.playImmediately(atRate: 2) } else { player.play() }
    for _ in 0..<(growing ? 220 : 120) {
      if collector.text.contains("İkinci satır") { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    #expect(collector.text.contains("İkinci satır, virgül korunur"),
      "AVPlayer selected Turkish but decoded no cue; time=\(player.currentTime().seconds), errors=\(String(describing: item.errorLog()?.events))")
    #expect(!collector.text.contains("English"))
    if let time = collector.secondCueTime {
      if growing {
        #expect(abs(time - 28.5) < 0.1, "caption lost sync when the event playlist grew")
      } else {
        #expect(time < 3, "caption is late: source PTS was used instead of the fragment clock")
      }
    }
  }

  // Fixture: 8 seconds of H.264, 32 kHz English and 48 kHz Turkish AAC,
  // English and Turkish ASS streams. The selected streams are not the first ones.
  @Test(arguments: [false, true])
  func selectedStreamsSurviveRemux(fmp4: Bool) async throws {
    try await checkRemux(fmp4: fmp4, start: 0)
  }

  @Test(arguments: [false, true])
  func selectedSubtitlesSurviveResume(fmp4: Bool) async throws {
    try await checkRemux(fmp4: fmp4, start: 4)
  }

  @Test(arguments: [false, true])
  func selectedSubtitlesArePublishedDuringLivePlayback(fmp4: Bool) async throws {
    try await checkRemux(fmp4: fmp4, start: 0, isLive: true)
  }

  @Test(arguments: [false, true])
  func externalSubtitlesArePublishedOnBothContainers(fmp4: Bool) async throws {
    try await checkRemux(fmp4: fmp4, start: 0, external: true)
  }

  private func checkRemux(fmp4: Bool, start: Double, isLive: Bool = false, external: Bool = false) async throws {
    let source = try #require(Bundle(for: CastTracksFixtureBundle.self)
      .url(forResource: "selected-tracks", withExtension: "mkv"))
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("cast-tracks-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let subtitleFile = directory.appendingPathComponent("selected.srt")
    if external {
      try "1\n00:00:04,000 --> 00:00:07,500\nİkinci satır, virgül korunur\n".write(
        to: subtitleFile, atomically: true, encoding: .utf8
      )
    }
    let writer = RemuxHLSWriter(
      sourceURL: source, outputDirectory: directory, startSeconds: start,
      isLive: isLive, userAgent: nil, forcedFormat: fmp4 ? .fmp4 : .mpegTS,
      subtitleFileURL: external ? subtitleFile : nil,
      subtitleName: "Türkçe", subtitleLanguage: "tur",
      audioStreamIndex: 2, subtitleStreamIndex: 4, subtitleDelaySeconds: 0.25
    )
    defer {
      writer.cancel()
      if writer.isClosed { try? FileManager.default.removeItem(at: directory) }
    }
    writer.onError = {
      // A finite file stands in for live packets; its EOF is intentionally a
      // disconnect. The segments published before that disconnect must have captions.
      if isLive, case RemuxHLSWriter.RemuxError.readFailed(-541_478_725) = $0 { return }
      Issue.record("remux failed: \($0)")
    }
    writer.start()
    for _ in 0..<100 {
      if writer.isClosed { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    #expect(writer.isClosed)
    #expect(writer.clientPlaylistFileName == "master.m3u8")
    let playlist = try String(contentsOf: writer.playlistURL, encoding: .utf8)
    if !isLive { #expect(playlist.contains("#EXT-X-ENDLIST")) }
    let names = playlist.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
    var videoData = fmp4 ? try Data(contentsOf: directory.appendingPathComponent("init.mp4")) : Data()
    for name in names { videoData += try Data(contentsOf: directory.appendingPathComponent(String(name))) }
    let combined = directory.appendingPathComponent(fmp4 ? "combined.mp4" : "combined.ts")
    try videoData.write(to: combined)
    #expect(try audioSampleRate(in: combined) == 48_000, "cast silently picked the first audio")

    let subtitles = try String(contentsOf: directory.appendingPathComponent("subs.m3u8"), encoding: .utf8)
    if !isLive { #expect(subtitles.contains("#EXT-X-ENDLIST")) }
    let vttNames = subtitles.split(separator: "\n").filter { $0.hasSuffix(".vtt") }
    #expect(vttNames.count == names.count, "subtitle and video segment windows differ")
    let vttDocuments = try vttNames.map {
      try String(contentsOf: directory.appendingPathComponent(String($0)), encoding: .utf8)
    }
    let documents = vttDocuments.joined(separator: "\n")
    #expect(documents.contains("İkinci satır, virgül korunur"))
    #expect(!documents.contains("English"))
    #expect(!documents.contains("Default,,"))
    #expect(documents.contains("X-TIMESTAMP-MAP=MPEGTS:"))
    let firstMap = try #require(vttDocuments.first?.split(separator: "\n").first { $0.hasPrefix("X-TIMESTAMP-MAP") })
    let clockText = try #require(firstMap.components(separatedBy: "MPEGTS:").last?.components(separatedBy: ",").first)
    let subtitleClock = try #require(Double(clockText)) / 90_000
    #expect(abs(try firstVideoSeconds(in: combined, ignoreEditList: fmp4) - subtitleClock) < 0.002,
      "subtitle timestamp map does not match the actual video PTS")
    // The per-content delay must also reach the receiver's captions.
    // AAC priming can make the demuxer's start time negative. Match the same
    // source origin instead of assuming this file begins at exactly zero.
    let origin = external ? 0 : try sourceStartSeconds(in: source)
    let expected = AirPlaySubtitleRendition.build(from: [SubtitleEntry(
      startTime: 4 - origin + 0.25, endTime: 7.5 - origin + 0.25, text: ""
    )]).webVTT.split(separator: "\n").first { $0.contains("-->") }
    #expect(documents.contains(String(try #require(expected))))
  }

  private func audioSampleRate(in url: URL) throws -> Int32 {
    var input: UnsafeMutablePointer<AVFormatContext>?
    defer { avformat_close_input(&input) }
    #expect(avformat_open_input(&input, url.path, nil, nil) >= 0)
    let context = try #require(input)
    #expect(avformat_find_stream_info(context, nil) >= 0)
    for index in 0..<Int(context.pointee.nb_streams) {
      if let parameters = context.pointee.streams[index]?.pointee.codecpar,
         parameters.pointee.codec_type == AVMEDIA_TYPE_AUDIO {
        return parameters.pointee.sample_rate
      }
    }
    Issue.record("no audio in cast output")
    return 0
  }

  private func sourceStartSeconds(in url: URL) throws -> Double {
    var input: UnsafeMutablePointer<AVFormatContext>?
    defer { avformat_close_input(&input) }
    #expect(avformat_open_input(&input, url.path, nil, nil) >= 0)
    let context = try #require(input)
    #expect(avformat_find_stream_info(context, nil) >= 0)
    return context.pointee.start_time == Int64.min ? 0 : Double(context.pointee.start_time) / 1_000_000
  }

  private func firstVideoSeconds(in url: URL, ignoreEditList: Bool = false) throws -> Double {
    var input: UnsafeMutablePointer<AVFormatContext>?
    var options: OpaquePointer?
    if ignoreEditList { av_dict_set(&options, "ignore_editlist", "1", 0) }
    defer { avformat_close_input(&input); av_dict_free(&options) }
    #expect(avformat_open_input(&input, url.path, nil, &options) >= 0)
    let context = try #require(input)
    #expect(avformat_find_stream_info(context, nil) >= 0)
    var packet = AVPacket()
    defer { av_packet_unref(&packet) }
    while av_read_frame(context, &packet) >= 0 {
      let stream = try #require(context.pointee.streams[Int(packet.stream_index)])
      if stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO, packet.pts != Int64.min {
        return Double(packet.pts) * Double(stream.pointee.time_base.num) / Double(stream.pointee.time_base.den)
      }
      av_packet_unref(&packet)
    }
    Issue.record("no video packet in remux")
    return -1
  }

  @Test func exactSelectionDoesNotFallBackToFirstAudio() {
    #expect(RemuxHLSWriter.preferredAudioCandidate(sampleRates: [32_000, 48_000], selectedIndex: 1) == 1)
    #expect(RemuxHLSWriter.preferredAudioCandidate(sampleRates: [48_000, 0], selectedIndex: 1) == 1)
    #expect(RemuxHLSWriter.preferredAudioCandidate(sampleRates: [0, 48_000], selectedIndex: 99) == 1)
  }

  @Test func timestampMapUsesTheVideoClockAtResume() {
    let built = AirPlaySubtitleRendition.build(from: [], mpegtsClock: 325_800_000, localSeconds: 10)
    #expect(built.webVTT.contains("MPEGTS:325800000,LOCAL:00:00:10.000"))
  }

  @Test func subtitleMasterUsesBCP47LanguageTags() {
    for (container, expected) in [("tur", "tr"), ("eng_US", "en-US"), ("tr", "tr")] {
      let playlist = AirPlaySubtitleRendition.masterPlaylist(
        videoPlaylistFileName: "stream.m3u8", subtitlePlaylistFileName: "subs.m3u8",
        name: "Subtitles", languageCode: container
      )
      #expect(playlist.contains("LANGUAGE=\"\(expected)\""))
    }
  }

  @Test func subtitleMasterDescribesTheMeasuredVideoBandwidth() {
    let bandwidth = RemuxHLSWriter.variantBandwidth(
      segmentBytes: 9_473_312, duration: 3.920, previous: 6_000_000
    )
    #expect(bandwidth > 19_000_000)
    #expect(RemuxHLSWriter.variantBandwidth(
      segmentBytes: 1_000, duration: 4, previous: bandwidth
    ) == bandwidth)
    let playlist = AirPlaySubtitleRendition.masterPlaylist(
      videoPlaylistFileName: "stream.m3u8", subtitlePlaylistFileName: "subs.m3u8",
      name: "Türkçe", languageCode: "tur", bandwidth: bandwidth, version: 7
    )
    #expect(playlist.contains("BANDWIDTH=\(bandwidth),"))
    #expect(playlist.contains("#EXT-X-VERSION:7"))
  }

  @Test func assTextKeepsDialogueCommasAndLineBreaks() {
    #expect(TextSubtitleDecoder.plainText(fromASS: #"{\i1}Hello, world{\i0}\Nsecond\hline"#)
      == "Hello, world\nsecond line")
  }

  @Test @MainActor
  func castTakeoverRetainsStreamMetadataWithoutSelectingAClosedSource() async throws {
    let source = try #require(Bundle(for: CastTracksFixtureBundle.self)
      .url(forResource: "selected-tracks", withExtension: "mkv"))
    try AVAudioSession.sharedInstance().setCategory(.playback)
    try AVAudioSession.sharedInstance().setActive(true)
    let engine = KSPlayerEngine()
    defer { engine.dispose() }
    engine.load(source, play: true, startSeconds: nil, liveLowLatency: false, userAgent: nil)
    for _ in 0..<100 {
      if engine.isPlaybackEstablished { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    #expect(engine.isPlaybackEstablished)
    var subtitleID: Int?
    engine.reloadTrackList { _, _, subtitles, _, _, _ in
      subtitleID = subtitles.first { $0.langCode == "tur" }?.id
    }
    let id = try #require(subtitleID)
    #expect(engine.embeddedSubtitleStreamIndex(id: id) == 4)
    #expect(id != 4, "menu ids and FFmpeg stream indexes must not be confused")
    engine.selectSubtitleTrack(id: id)
    engine.stopPlayback()
    #expect(engine.layer == nil)
    #expect(engine.embeddedSubtitleStreamIndex(id: id) == 4)
    engine.selectSubtitleTrack(id: id)
    engine.selectSubtitleTrack(id: -1)
    #expect(engine.subtitleText == nil)
  }
}

@Suite("AudioOutputRecovery", .serialized)
@MainActor
struct AudioOutputRecoveryTests {
  private func playingOutput() throws -> RecoveringAudioEnginePlayer {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback)
    try session.setActive(true)
    let output = RecoveringAudioEnginePlayer()
    output.prepare(audioFormat: try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)))
    output.play()
    #expect(output.engine.isRunning)
    return output
  }

  @Test func stoppedEngineRestartsAfterConfigurationChange() async throws {
    let output = try playingOutput()
    defer { output.pause() }
    output.engine.stop()
    NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: output.engine)
    try await Task.sleep(for: .milliseconds(600))
    #expect(output.engine.isRunning)
  }

  @Test func spontaneousStopRecoversWithoutRouteChange() async throws {
    let output = try playingOutput()
    defer { output.pause() }
    output.engine.stop()
    output.recoverIfStopped()
    try await Task.sleep(for: .milliseconds(600))
    #expect(output.engine.isRunning)
  }

  @Test func pausedOutputStaysPausedAfterConfigurationChange() async throws {
    let output = try playingOutput()
    output.pause()
    NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: output.engine)
    try await Task.sleep(for: .milliseconds(600))
    #expect(!output.engine.isRunning)
  }

  @Test func pauseCancelsPendingRecovery() async throws {
    let output = try playingOutput()
    output.engine.stop()
    output.flush()
    output.pause()
    try await Task.sleep(for: .milliseconds(600))
    #expect(!output.engine.isRunning)
  }
}
