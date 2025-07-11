import 'dart:async';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/watch_history.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/event_bus.dart';
import 'package:another_iptv_player/services/watch_history_service.dart';
import 'package:another_iptv_player/utils/subtitle_configuration.dart';
import 'package:another_iptv_player/widgets/video_widget.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import '../../models/content_type.dart';
import '../../services/player_state.dart';
import '../../services/service_locator.dart';
import '../../utils/audio_handler.dart';
import '../../utils/build_media_url.dart';

class PlayerWidget extends StatefulWidget {
  final ContentItem contentItem;
  final double? aspectRatio;
  final bool showControls;
  final bool showInfo;
  final VoidCallback? onFullscreen;
  final List<ContentItem>? queue;

  const PlayerWidget({
    super.key,
    required this.contentItem,
    this.aspectRatio,
    this.showControls = true,
    this.showInfo = false,
    this.onFullscreen,
    this.queue,
  });

  @override
  State<PlayerWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget>
    with WidgetsBindingObserver {
  late StreamSubscription videoTrackSubscription;
  late StreamSubscription audioTrackSubscription;
  late StreamSubscription subtitleTrackSubscription;
  late StreamSubscription contentItemIndexChangedSubscription;

  late Player _player;
  VideoController? _videoController;
  late WatchHistoryService watchHistoryService;
  final MyAudioHandler _audioHandler = getIt<MyAudioHandler>();
  List<ContentItem>? _queue;
  late ContentItem contentItem;

  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    contentItem = widget.contentItem;
    _queue = widget.queue;
    PlayerState.title = widget.contentItem.name;
    _player = Player(configuration: PlayerConfiguration(osc: false));
    watchHistoryService = WatchHistoryService();

    super.initState();
    videoTrackSubscription = EventBus()
        .on<VideoTrack>('video_track_changed')
        .listen((VideoTrack data) async {
          _player.setVideoTrack(data);
          await UserPreferences.setVideoTrack(data.id);
        });

    audioTrackSubscription = EventBus()
        .on<AudioTrack>('audio_track_changed')
        .listen((AudioTrack data) async {
          _player.setAudioTrack(data);
          await UserPreferences.setAudioTrack(data.language ?? 'null');
        });

    subtitleTrackSubscription = EventBus()
        .on<SubtitleTrack>('subtitle_track_changed')
        .listen((SubtitleTrack data) async {
          _player.setSubtitleTrack(data);
          await UserPreferences.setSubtitleTrack(data.language ?? 'null');
        });

    _initializePlayer();
  }

  @override
  void dispose() {
    _player.dispose();
    _audioHandler.setPlayer(null);
    _audioHandler.stop();
    videoTrackSubscription.cancel();
    audioTrackSubscription.cancel();
    subtitleTrackSubscription.cancel();
    contentItemIndexChangedSubscription.cancel();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    if (!mounted) return;

    PlayerState.subtitleConfiguration = await getSubtitleConfiguration();

    PlayerState.backgroundPlay = await UserPreferences.getBackgroundPlay();
    _audioHandler.setPlayer(_player);
    _videoController = VideoController(_player);

    var watchHistory = await watchHistoryService.getWatchHistory(
      AppState.currentPlaylist!.id,
      contentItem.id,
    );

    List<MediaItem> mediaItems = [];
    var mediaUrl = buildMediaUrl(contentItem);
    var currentItemIndex = 0;

    if (_queue != null) {
      for (int i = 0; i < _queue!.length; i++) {
        final item = _queue![i];
        final itemWatchHistory = await watchHistoryService.getWatchHistory(
          AppState.currentPlaylist!.id,
          item.id,
        );

        mediaItems.add(
          MediaItem(
            id: item.id.toString(),
            title: item.name,
            artist: _getContentTypeDisplayName(),
            album: AppState.currentPlaylist?.name ?? '',
            artUri: item.imagePath != null ? Uri.parse(item.imagePath!) : null,
            playable: true,
            extras: {
              'url': buildMediaUrl(item),
              'startPosition':
                  itemWatchHistory?.watchDuration?.inMilliseconds ?? 0,
            },
          ),
        );

        if (item.id == contentItem.id) {
          currentItemIndex = i;
        }
      }

      await _audioHandler.setQueue(mediaItems, initialIndex: currentItemIndex);

      var playlist = mediaItems.map((mediaItem) {
        final url = mediaItem.extras!['url'] as String;
        final startMs = mediaItem.extras!['startPosition'] as int;
        return Media(url, start: Duration(milliseconds: startMs));
      }).toList();

      await _player.open(
        Playlist(playlist, index: currentItemIndex),
        play: true,
      );
    } else {
      final mediaItem = MediaItem(
        id: contentItem.id.toString(),
        title: contentItem.name,
        artist: _getContentTypeDisplayName(),
        artUri: contentItem.imagePath != null
            ? Uri.parse(contentItem.imagePath!)
            : null,
        extras: {
          'url': mediaUrl,
          'startPosition': watchHistory?.watchDuration?.inMilliseconds ?? 0,
        },
      );

      await _audioHandler.setQueue([mediaItem]);

      await _player.open(
        Playlist([
          Media(mediaUrl, start: watchHistory?.watchDuration ?? Duration()),
        ]),
        play: true,
      );
    }

    _player.stream.tracks.listen((event) async {
      if (!mounted) return;

      PlayerState.videos = event.video;
      PlayerState.audios = event.audio;
      PlayerState.subtitles = event.subtitle;

      EventBus().emit('player_tracks', event);

      await _player.setVideoTrack(
        VideoTrack(await UserPreferences.getVideoTrack(), null, null),
      );

      var selectedAudioLanguage = await UserPreferences.getAudioTrack();
      var possibleAudioTrack = event.audio.firstWhere(
        (x) => x.language == selectedAudioLanguage,
        orElse: AudioTrack.auto,
      );

      await _player.setAudioTrack(possibleAudioTrack);

      var selectedSubtitleLanguage = await UserPreferences.getSubtitleTrack();
      var possibleSubtitleLanguage = event.subtitle.firstWhere(
        (x) => x.language == selectedSubtitleLanguage,
        orElse: SubtitleTrack.auto,
      );

      await _player.setSubtitleTrack(possibleSubtitleLanguage);
    });

    _player.stream.track.listen((event) async {
      if (!mounted) return;

      PlayerState.selectedVideo = _player.state.track.video;
      PlayerState.selectedAudio = _player.state.track.audio;
      PlayerState.selectedSubtitle = _player.state.track.subtitle;

      var volume = await UserPreferences.getVolume();
      await _player.setVolume(volume);
    });

    _player.stream.volume.listen((event) async {
      await UserPreferences.setVolume(event);
    });

    _player.stream.position.listen((position) async {
      _player.state.playlist.medias[currentItemIndex] = Media(
        buildMediaUrl(contentItem),
        start: position,
      );

      await watchHistoryService.saveWatchHistory(
        WatchHistory(
          playlistId: AppState.currentPlaylist!.id,
          contentType: contentItem.contentType,
          streamId: contentItem.id,
          lastWatched: DateTime.now(),
          title: contentItem.name,
          imagePath: contentItem.imagePath,
          totalDuration: _player.state.duration,
          watchDuration: position,
        ),
      );
    });

    _player.stream.error.listen((error) {
      print('PLAYER ERROR -> $error');
    });

    _player.stream.playlist.listen((playlist) {
      if (!mounted) return;
      currentItemIndex = playlist.index;
      contentItem = _queue?[playlist.index] ?? widget.contentItem;
      PlayerState.title = contentItem.name;
      EventBus().emit('player_content_item', contentItem);
      EventBus().emit('player_content_item_index', playlist.index);
    });

    contentItemIndexChangedSubscription = EventBus()
        .on<int>('player_content_item_index_changed')
        .listen((int index) {
          _player.jump(index);
        });

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.detached:
        await _player.dispose();
        _audioHandler.setPlayer(null);
        await _audioHandler.stop();
        break;
      default:
        break;
    }
  }

  String _getContentTypeDisplayName() {
    switch (widget.contentItem.contentType) {
      case ContentType.liveStream:
        return 'Canlı Yayın';
      case ContentType.vod:
        return 'Film';
      case ContentType.series:
        return 'Dizi';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.shortestSide >= 600;
    final isLandscape = screenSize.width > screenSize.height;
    double calculateAspectRatio() {
      if (widget.aspectRatio != null) return widget.aspectRatio!;

      if (isTablet) {
        return isLandscape ? 21 / 9 : 16 / 9;
      }
      return 16 / 9;
    }

    double? calculateMaxHeight() {
      if (isTablet) {
        if (isLandscape) {
          return screenSize.height * 0.6;
        } else {
          return screenSize.height * 0.4;
        }
      }
      return null;
    }

    Widget playerWidget = AspectRatio(
      aspectRatio: calculateAspectRatio(),
      child: isLoading
          ? Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          : _buildPlayerContent(),
    );

    if (isTablet) {
      final maxHeight = calculateMaxHeight();
      if (maxHeight != null) {
        playerWidget = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: playerWidget,
        );
      }
    }

    return Container(
      color: Colors.black,
      child: Column(children: [playerWidget]),
    );
  }

  Widget _buildPlayerContent() {
    if (hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                errorMessage,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    }

    return Stack(
      children: [
        getVideo(context, _videoController!, PlayerState.subtitleConfiguration),

        if (widget.onFullscreen != null)
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: widget.onFullscreen,
              icon: const Icon(Icons.fullscreen, color: Colors.white, size: 24),
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
            ),
          ),
      ],
    );
  }
}
