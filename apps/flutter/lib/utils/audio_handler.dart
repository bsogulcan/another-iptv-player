import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;

Future<MyAudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.ogos.anotheriptvplayer',
      androidNotificationChannelName: 'Another IPTV Player',
      androidNotificationOngoing: false,
      androidShowNotificationBadge: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  MyAudioHandler() {
    _initAudioSession();
  }

  Player? _player;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playbackStateSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _playlistSubscription;

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;

      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );

      await session.setActive(true);

      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player?.setVolume(_player!.state.volume * 0.2);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              _player?.pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player?.setVolume(_player!.state.volume / 0.2);
              break;
            case AudioInterruptionType.pause:
              _player?.play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      session.becomingNoisyEventStream.listen((_) {
        _player?.pause();
      });
    } catch (e) {
      print('Audio session configuration error: $e');
    }
  }

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
    _playlistSubscription?.cancel();
  }

  void dispose() {
    _clearPlayerListeners();
  }

  void _setupPlayerListeners() {
    if (_player == null) return;

    _positionSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _playlistSubscription?.cancel();

    _positionSubscription = _player!.stream.position.listen((position) {
      playbackState.add(
        playbackState.value.copyWith(
          updatePosition: position,
          bufferedPosition: position,
        ),
      );
    });

    _playbackStateSubscription = _player!.stream.playing.listen((playing) {
      final state = PlaybackState(
        controls: [
          if (queue.value.length > 1) MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          if (queue.value.length > 1) MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: _player!.state.position,
        bufferedPosition: _player!.state.position,
        speed: _player!.state.rate,
        queueIndex: _getCurrentQueueIndex(),
      );

      playbackState.add(state);
    });

    _durationSubscription = _player!.stream.duration.listen((duration) {
      if (mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });

    _playlistSubscription = _player!.stream.playlist.listen((playlist) {
      if (playlist.medias.isNotEmpty && playlist.index < queue.value.length) {
        final currentItem = queue.value[playlist.index];
        mediaItem.add(currentItem);
      }
    });
  }

  Future<void> setQueue(
    List<MediaItem> newQueue, {
    int initialIndex = 0,
  }) async {
    queue.add(newQueue);

    if (newQueue.isNotEmpty) {
      await _updateQueueIndex(initialIndex);
    }
  }

  void setCurrentMediaItem({
    required String title,
    String? artist,
    String? artUri,
    Duration? duration,
  }) {
    final item = MediaItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      artist: artist ?? '',
      artUri: artUri != null ? Uri.parse(artUri) : null,
      duration: duration,
    );

    queue.add([item]);
    mediaItem.add(item);
  }

  Future<void> _updateQueueIndex(int index) async {
    if (index >= 0 && index < queue.value.length) {
      mediaItem.add(queue.value[index]);
    }
  }

  int? _getCurrentQueueIndex() {
    if (_player == null) return null;
    final currentIndex = _player!.state.playlist.index;
    return currentIndex >= 0 && currentIndex < queue.value.length
        ? currentIndex
        : null;
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
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    await _player?.next();
  }

  @override
  Future<void> skipToPrevious() async {
    await _player?.previous();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (_player != null && index >= 0 && index < queue.value.length) {
      await _player!.jump(index);
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final newQueue = List<MediaItem>.from(queue.value)..add(mediaItem);
    queue.add(newQueue);
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final newQueue = List<MediaItem>.from(queue.value)
      ..removeWhere((item) => item.id == mediaItem.id);
    queue.add(newQueue);
  }
}
