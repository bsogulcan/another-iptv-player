import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class MacPlaybackTracks: ObservableObject {
  enum Kind { case video, audio, subtitles }
  weak var cast: CastController?
  private let engine: KSPlayerEngine
  private var ready: AnyCancellable?
  @Published private var contentKey: String?
  @Published private(set) var video: [TrackMenuOption] = []
  @Published private(set) var audio: [TrackMenuOption] = []
  @Published private(set) var subtitles: [TrackMenuOption] = []
  @Published private(set) var videoID = -1
  @Published private(set) var audioID = -1
  @Published private(set) var subtitleID = -1
  @Published private(set) var files: [URL] = []
  @Published private(set) var subtitleDelay = 0.0
  @Published private(set) var audioDelay = AudioDelayPersistence.load()

  init(engine: KSPlayerEngine) {
    self.engine = engine
    ready = engine.$isPlaybackEstablished.removeDuplicates().filter { $0 }.receive(
      on: DispatchQueue.main
    )
    .sink { [weak self] _ in
      guard let self, self.engine.isPlaybackEstablished, let key = contentKey else { return }
      let selected = ImportedSubtitleStore.selectedFileName(for: key)
      for file in files {
        engine.addExternalSubtitle(
          filePath: file.path, title: file.lastPathComponent,
          select: file.lastPathComponent == selected)
      }
      refresh()
      let prefs = PlaybackTrackPreferences.load()
      if let id = PlaybackTrackPreferences.pickVideo(from: video, prefs: prefs) {
        engine.selectVideoTrack(id: id)
      }
      if let id = PlaybackTrackPreferences.pickAudio(from: audio, prefs: prefs) {
        engine.selectAudioTrack(id: id)
      }
      if !files.contains(where: { $0.lastPathComponent == selected }),
        let id = PlaybackTrackPreferences.pickSubtitle(from: subtitles, prefs: prefs)
      {
        engine.selectSubtitleTrack(id: id)
      }
      engine.setAudioDelay(seconds: audioDelay)
      engine.setSubDelay(seconds: subtitleDelay)
      refresh()
    }
  }

  func prepare(_ key: String?) {
    contentKey = key
    files = key.map { ImportedSubtitleStore.subtitleFiles(for: $0) } ?? []
    subtitleDelay = key.map { SubtitleDelayStore.delaySeconds(for: $0) } ?? 0
    video = []
    audio = []
    subtitles = []
    videoID = -1
    audioID = -1
    subtitleID = -1
  }
  private func remuxSubtitles(_ catalog: RemuxSourceTracks) -> [TrackMenuOption] {
    [TrackMenuOption(id: -1, title: L("player.subtitle_off"))] + catalog.subtitles
      + files.enumerated().map {
        TrackMenuOption(
          id: Int.min + $0.offset, title: $0.element.lastPathComponent, isExternal: true)
      }
  }

  func applyRemuxCatalog(_ catalog: RemuxSourceTracks) {
    video = []
    audio = catalog.audio
    subtitles = remuxSubtitles(catalog)
    audioID = catalog.selectedAudioID
    let imported = contentKey.flatMap { ImportedSubtitleStore.selectedFileName(for: $0) }
    subtitleID =
      subtitles.first { $0.isExternal && $0.title == imported }?.id ?? catalog.selectedSubtitleID
  }

  func refresh() {
    if cast?.isPresenting == true { return }
    engine.reloadTrackList { [weak self] video, audio, subs, vid, aid, sid in
      guard let self else { return }
      self.video = video
      self.audio = audio
      subtitles = subs
      videoID = vid
      audioID = aid
      subtitleID = sid
    }
  }
  func select(_ kind: Kind, id: Int) {
    switch kind {
    case .video:
      guard let track = video.first(where: { $0.id == id }) else { return }
      engine.selectVideoTrack(id: id)
      videoID = id
      PlaybackTrackPreferences.saveVideo(from: track)
    case .audio:
      guard let track = audio.first(where: { $0.id == id }) else { return }
      if cast?.updateRemuxTracks({ $0.audioStreamIndex = id }) != true {
        engine.selectAudioTrack(id: id)
      }
      audioID = id
      PlaybackTrackPreferences.saveAudio(from: track)
    case .subtitles:
      guard let track = subtitles.first(where: { $0.id == id }) else { return }
      if let cast, cast.isPresenting {
        let file = files.first { track.isExternal && $0.lastPathComponent == track.title }
        cast.updateRemuxTracks {
          $0.subtitleFileURL = file
          $0.subtitleStreamIndex = id >= 0 ? id : nil
          $0.subtitleName = track.title
          $0.subtitleLanguage = track.langCode
        }
      } else {
        engine.selectSubtitleTrack(id: id)
      }
      subtitleID = id
      PlaybackTrackPreferences.saveSubtitle(from: track)
      if let key = contentKey {
        ImportedSubtitleStore.setSelectedFileName(
          track.isExternal && files.contains(where: { $0.lastPathComponent == track.title })
            ? track.title : nil, for: key)
      }
    }
  }
  func add(_ url: URL) throws {
    guard let key = contentKey else { throw CocoaError(.fileNoSuchFile) }
    let file = try ImportedSubtitleStore.importFile(at: url, for: key)
    let name = file.lastPathComponent
    if let cast, cast.isPresenting, let catalog = cast.sourceTracks {
      files = ImportedSubtitleStore.subtitleFiles(for: key)
      subtitles = remuxSubtitles(catalog)
      if let added = subtitles.first(where: { $0.isExternal && $0.title == name }) {
        select(.subtitles, id: added.id)
      }
      return
    }
    if let old = subtitles.first(where: { $0.isExternal && $0.title == name }) {
      engine.removeExternalSubtitle(id: old.id)
    }
    ImportedSubtitleStore.setSelectedFileName(name, for: key)
    engine.addExternalSubtitle(filePath: file.path, title: name, select: true)
    files = ImportedSubtitleStore.subtitleFiles(for: key)
    refresh()
  }
  func remove(_ file: URL) {
    guard let key = contentKey, files.contains(file) else { return }
    if let cast, cast.isPresenting, let catalog = cast.sourceTracks {
      if subtitles.first(where: { $0.id == subtitleID })?.title == file.lastPathComponent {
        select(.subtitles, id: -1)
      }
      ImportedSubtitleStore.removeFile(file, for: key)
      files = ImportedSubtitleStore.subtitleFiles(for: key)
      applyRemuxCatalog(catalog)
      return
    }
    if let old = subtitles.first(where: { $0.isExternal && $0.title == file.lastPathComponent }) {
      engine.removeExternalSubtitle(id: old.id)
    }
    ImportedSubtitleStore.removeFile(file, for: key)
    files = ImportedSubtitleStore.subtitleFiles(for: key)
    refresh()
  }
  func setSubtitleDelay(_ value: Double) {
    guard let key = contentKey else { return }
    let next = SubtitleDelayStore.clamp(value)
    guard subtitleDelay != next else { return }
    subtitleDelay = next
    if cast?.isRemuxing == true { cast?.updateRemuxTracks { $0.subtitleDelaySeconds = next } }
    engine.setSubDelay(seconds: subtitleDelay)
    SubtitleDelayStore.setDelaySeconds(subtitleDelay, for: key)
  }
  func setAudioDelay(_ value: Double) {
    AudioDelayPersistence.save(value)
    audioDelay = AudioDelayPersistence.load()
    engine.setAudioDelay(seconds: audioDelay)
  }
}

extension MacPlaybackTracks: SubtitleStyleEditing {
  var subtitleEditingContentKey: String? { contentKey }
  var subtitleDelaySeconds: Double { subtitleDelay }
  func applySubtitleAppearanceSettings(_ settings: SubtitleAppearanceSettings) {
    SubtitleAppearancePersistence.save(settings)
    engine.applySubtitleAppearanceFromSettings(settings)
  }
  func applySubtitleDelaySeconds(_ seconds: Double) { engine.setSubDelay(seconds: seconds) }
  func commitSubtitleDelaySeconds(_ seconds: Double) { setSubtitleDelay(seconds) }
}

struct MacTrackMenu: View {
  let editStyle: () -> Void
  @ObservedObject var tracks: MacPlaybackTracks
  let supportsAudioDelay: Bool
  @Binding var presented: Bool
  @State private var importing = false
  @State private var failure: String?
  var body: some View {
    Button {
      tracks.refresh()
      presented.toggle()
    } label: {
      Label(L("player.tracks.title"), systemImage: "captions.bubble")
    }
    .labelStyle(.iconOnly).help(L("player.tracks.title"))
    .popover(isPresented: $presented) {
      Form {
        Section(L("player.tracks.title")) {
          picker(L("player.tracks.video"), tracks.video, tracks.videoID, .video)
          picker(L("player.tracks.audio"), tracks.audio, tracks.audioID, .audio)
          picker(L("player.tracks.subtitle"), tracks.subtitles, tracks.subtitleID, .subtitles)
        }
        Button(L("subtitle.settings_title")) {
          presented = false
          editStyle()
        }
        Section(L("player.subtitle_import.section")) {
          ForEach(tracks.files, id: \.self) { file in
            HStack {
              Text(verbatim: file.lastPathComponent).lineLimit(1)
              Spacer()
              Button(L("common.delete"), systemImage: "trash", role: .destructive) {
                tracks.remove(file)
              }.labelStyle(.iconOnly)
                .accessibilityValue(Text(verbatim: file.lastPathComponent))
                .help(Text(verbatim: file.lastPathComponent))
            }
          }
          Button(L("player.subtitle_import.button"), systemImage: "folder") { importing = true }
        }
        Section {
          Stepper(
            value: Binding(get: { tracks.subtitleDelay }, set: tracks.setSubtitleDelay),
            in: -10...10, step: 0.1
          ) {
            LabeledContent(
              L("subtitle.delay"),
              value: tracks.subtitleDelay.formatted(.number.precision(.fractionLength(1))) + " s")
          }
          if supportsAudioDelay {
            Stepper(
              value: Binding(get: { tracks.audioDelay }, set: tracks.setAudioDelay),
              in: AudioDelayPersistence.range, step: AudioDelayPersistence.step
            ) {
              LabeledContent(
                L("player.audio_delay.label"),
                value: tracks.audioDelay.formatted(.number.precision(.fractionLength(3))) + " s")
            }
          }
        }
      }.formStyle(.grouped).frame(width: 400, height: 355)
        .fileImporter(
          isPresented: $importing,
          allowedContentTypes: ["srt", "vtt", "ass", "ssa"].compactMap {
            UTType(filenameExtension: $0)
          }
        ) { result in
          do { try tracks.add(result.get()) } catch {
            if !isFileImportCancellation(error) {
              failure = error.localizedDescription
            }
          }
        }.macError($failure)
    }
  }
  @ViewBuilder private func picker(
    _ label: String, _ options: [TrackMenuOption], _ selected: Int, _ kind: MacPlaybackTracks.Kind
  ) -> some View {
    if !options.isEmpty {
      Picker(label, selection: Binding(get: { selected }, set: { tracks.select(kind, id: $0) })) {
        ForEach(options) { track in
          Text([track.title, track.detail].compactMap { $0 }.joined(separator: " · ")).tag(track.id)
        }
      }
    }
  }
}
