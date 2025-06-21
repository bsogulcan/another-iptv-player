import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:iptv_player/database/database.dart';
import 'package:iptv_player/models/playlist_content_model.dart';
import 'package:iptv_player/models/watch_history.dart';
import 'package:iptv_player/repositories/user_prefrences.dart';
import 'package:iptv_player/services/event_bus.dart';
import 'package:iptv_player/services/watch_history_service.dart';
import 'package:iptv_player/views/widgets/video_widget.dart';
import 'package:media_kit/media_kit.dart' hide Playlist, PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:iptv_player/models/playlist_model.dart';
import '../../models/content_type.dart';
import '../../services/audio_service_manager.dart';
import '../../services/player_state.dart';
import '../../utils/audio_handler.dart';

class PlayerWidget extends StatefulWidget {
  final Playlist playlist;
  final ContentItem contentItem;
  final double? aspectRatio;
  final bool showControls;
  final bool showInfo;
  final VoidCallback? onFullscreen;

  const PlayerWidget({
    Key? key,
    required this.playlist,
    required this.contentItem,
    this.aspectRatio,
    this.showControls = true,
    this.showInfo = false,
    this.onFullscreen,
  }) : super(key: key);

  @override
  State<PlayerWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget>
    with WidgetsBindingObserver {
  late StreamSubscription videoTrackSubscription;
  late StreamSubscription audioTrackSubscription;
  late StreamSubscription subtitleTranckSubscription;
  late final GlobalKey<VideoState> key = GlobalKey<VideoState>();

  late Player _player;
  VideoController? _videoController;
  late WatchHistoryService watchHistoryService;
  MyAudioHandler? _audioHandler;

  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';

  @override
  void initState() {
    PlayerState.title = widget.contentItem.name;
    WidgetsBinding.instance.addObserver(this);
    _player = Player(configuration: PlayerConfiguration(osc: false));
    watchHistoryService = WatchHistoryService(AppDatabase());

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

    subtitleTranckSubscription = EventBus()
        .on<SubtitleTrack>('subtitle_track_changed')
        .listen((SubtitleTrack data) async {
          _player.setSubtitleTrack(data);
          await UserPreferences.setSubtitleTrack(data.language ?? 'null');
        });

    _initializeAudioService();
  }

  @override
  void dispose() {
    _player.dispose();
    _audioHandler?.setPlayer(null);
    videoTrackSubscription.cancel();
    audioTrackSubscription.cancel();
    subtitleTranckSubscription.cancel();
    super.dispose();
  }

  Future<void> _initializeAudioService() async {
    if (!mounted) return;
    _videoController = VideoController(_player);

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _audioHandler = await AudioServiceManager.instance.getAudioHandler();

    var mediaUrl = buildMediaUrl(widget.playlist, widget.contentItem);

    var watchHistory = await watchHistoryService.getWatchHistory(
      widget.playlist.id,
      widget.contentItem.id,
    );

    // Audio handler'a player'ı bağla
    _audioHandler?.setPlayer(_player);

    _audioHandler?.setCurrentMediaItem(
      title: widget.contentItem.name,
      artist: _getContentTypeDisplayName(),
      artUri: widget.contentItem.imagePath,
    );

    await _player.open(
      Media(mediaUrl, start: watchHistory?.watchDuration ?? Duration()),
      play: true,
    );

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      key.currentState?.enterFullscreen();
    });

    // try {
    //   await _player.stream.buffer.first;
    // } catch (e) {}

    // await _player.setVideoTrack(VideoTrack.auto());
    // await _player.setAudioTrack(AudioTrack.auto());
    // await _player.setSubtitleTrack(SubtitleTrack.auto());

    _player.stream.tracks.listen((event) async {
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
      await watchHistoryService.saveWatchHistory(
        WatchHistory(
          playlistId: widget.playlist.id,
          contentType: widget.contentItem.contentType,
          streamId: widget.contentItem.id,
          lastWatched: DateTime.now(),
          title: widget.contentItem.name,
          imagePath: widget.contentItem.imagePath,
          totalDuration: _player.state.duration,
          watchDuration: position,
        ),
      );
    });

    _player.stream.error.listen((error){
      print('PLAYER ERROR -> $error');
    });
  }

  String _getContentTypeDisplayName() {
    switch (widget.contentItem.contentType) {
      case ContentType.liveStream:
        return 'Canlı Yayın';
      case ContentType.vod:
        return 'Film';
      case ContentType.series:
        return 'Dizi';
      default:
        return 'Video';
    }
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      // App arka plana geçti, ses devam etsin
        break;
      case AppLifecycleState.resumed:
      // App ön plana geldi
        break;
      case AppLifecycleState.detached:
      // App kapanıyor, AudioService'i tamamen kapat
      //   AudioServiceManager.instance.stopAudioService();
        break;
      default:
        break;
        // await _audioHandler?.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: Colors.black,
        child: Column(
          children: [
            // Video Player Container
            AspectRatio(
              aspectRatio: widget.aspectRatio ?? 16 / 9,
              child: _buildPlayerContent(),
            ),
          ],
        ),
      ),
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
        getVideo(context, _videoController!, key),
        // Custom fullscreen button
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

  String _formatDuration(Duration duration) {
    String minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    if (duration.inHours > 0) {
      String hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

String buildMediaUrl(Playlist playlist, ContentItem contentItem) {
  switch (contentItem.contentType) {
    case ContentType.liveStream:
      return '${playlist.url}/${playlist.username}/${playlist.password}/${contentItem.id}';
    case ContentType.vod:
      return '${playlist.url}/movie/${playlist.username}/${playlist.password}/${contentItem.id}.${contentItem.containerExtension!}';
    case ContentType.series:
      return '${playlist.url}/series/${playlist.username}/${playlist.password}/${contentItem.id}.${contentItem.containerExtension!}';
  }
}
