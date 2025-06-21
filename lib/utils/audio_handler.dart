// services/audio_handler.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  static MyAudioHandler? _instance;
  // static MyAudioHandler get instance => _instance ??= MyAudioHandler._();

  // MyAudioHandler._();
  // Unnamed constructor ekle
  MyAudioHandler();

  Player? _player;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playbackStateSubscription;
  StreamSubscription? _durationSubscription;

  void setPlayer(Player? player) {
    _clearPlayerListeners();
    _player = player;
    if (_player != null) {
      _setupPlayerListeners();
    }
  }

  void _clearPlayerListeners() {
    _positionSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    _durationSubscription?.cancel();
  }

  void dispose() {
    _clearPlayerListeners();
  }

  void _setupPlayerListeners() {
    if (_player == null) return;

    _positionSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    _durationSubscription?.cancel();

    _positionSubscription = _player!.stream.position.listen((position) {
      playbackState.add(playbackState.value.copyWith(
        updatePosition: position,
        bufferedPosition: position,
      ));
    });

    _playbackStateSubscription = _player!.stream.playing.listen((playing) {
      playbackState.add(playbackState.value.copyWith(
        playing: playing,
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: AudioProcessingState.ready,
      ));
    });

    _durationSubscription = _player!.stream.duration.listen((duration) {
      if (mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });
  }

  // Override edilmiş updateMediaItem metodunu kaldır ve setMediaItem kullan
  void setCurrentMediaItem({
    required String title,
    String? artist,
    String? artUri,
    Duration? duration,
  }) {
    mediaItem.add(MediaItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      artist: artist ?? '',
      artUri: artUri != null ? Uri.parse(artUri) : null,
      duration: duration,
    ));
  }

  @override
  Future<void> play() async {
    await _player?.play();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    // Implement next track logic if needed
  }

  @override
  Future<void> skipToPrevious() async {
    // Implement previous track logic if needed
  }
}