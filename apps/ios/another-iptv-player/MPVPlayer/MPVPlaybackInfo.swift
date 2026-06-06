import Foundation

/// libmpv `Player.state` / `Player.stream` ile aynı bilgilerin Swift karşılığı.
/// Dart’taki `Duration` alanları burada **saniye** (`TimeInterval`) olarak tutulur.
public struct MPVPlaybackInfo: Equatable, Sendable {
  public var positionSeconds: TimeInterval
  public var durationSeconds: TimeInterval
  public var isPaused: Bool
  public var isBuffering: Bool
  public var isCompleted: Bool
  public var volume: Double
  public var playbackRate: Double
  public var videoDisplayWidth: Int
  public var videoDisplayHeight: Int
  public var mediaTitle: String

  public static let empty = MPVPlaybackInfo(
    positionSeconds: 0,
    durationSeconds: 0,
    isPaused: true,
    isBuffering: false,
    isCompleted: false,
    volume: 100,
    playbackRate: 1,
    videoDisplayWidth: 0,
    videoDisplayHeight: 0,
    mediaTitle: ""
  )

  /// MPVPlayer `playing` stream.
  public var isPlaying: Bool { !isPaused }
}
