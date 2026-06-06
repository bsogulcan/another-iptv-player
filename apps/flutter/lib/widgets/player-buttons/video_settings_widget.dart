import 'dart:async';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/services/event_bus.dart';
import 'package:another_iptv_player/services/player_state.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;

class VideoSettingsWidget extends StatefulWidget {
  const VideoSettingsWidget({super.key});

  @override
  State<VideoSettingsWidget> createState() => _VideoSettingsWidgetState();

  static void hideOverlay() {
    _VideoSettingsWidgetState.hideOverlay();
  }
}

class _VideoSettingsWidgetState extends State<VideoSettingsWidget> {
  static OverlayEntry? _globalOverlayEntry;
  static StreamSubscription? _globalToggleSubscription;
  static BuildContext? _globalContext;

  static void hideOverlay() {
    _globalOverlayEntry?.remove();
    _globalOverlayEntry = null;
    PlayerState.showVideoSettings = false;
  }

  @override
  void initState() {
    super.initState();
    _globalContext = context;

    _globalToggleSubscription ??=
        EventBus().on<bool>('toggle_video_settings').listen((bool show) {
      if (show) {
        if (_globalContext != null) {
          _showSettings(_globalContext!);
        }
      } else {
        hideOverlay();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _globalContext = context;
    return IconButton(
      icon: const Icon(Icons.settings, color: Colors.white),
      onPressed: () {
        if (_globalOverlayEntry == null) {
          _showSettings(context);
        } else {
          hideOverlay();
        }
      },
    );
  }

  void _showSettings(BuildContext context) {
    if (_globalOverlayEntry != null) return;

    final overlayContext = _globalContext ?? context;
    OverlayState? overlay;
    try {
      overlay = Overlay.of(overlayContext, rootOverlay: true);
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_globalOverlayEntry == null) {
          _showSettings(overlayContext);
        }
      });
      return;
    }

    final screenWidth = MediaQuery.of(overlayContext).size.width;
    final panelWidth = (screenWidth / 3).clamp(200.0, 400.0);

    _globalOverlayEntry = OverlayEntry(
      opaque: false,
      maintainState: true,
      builder: (context) => _VideoSettingsOverlay(
        width: panelWidth,
        onClose: hideOverlay,
      ),
    );

    overlay.insert(_globalOverlayEntry!);
    PlayerState.showVideoSettings = true;
  }
}

class _VideoSettingsOverlay extends StatefulWidget {
  final double width;
  final VoidCallback onClose;

  const _VideoSettingsOverlay({
    required this.width,
    required this.onClose,
  });

  @override
  State<_VideoSettingsOverlay> createState() => _VideoSettingsOverlayState();
}

class _VideoSettingsOverlayState extends State<_VideoSettingsOverlay> {
  late StreamSubscription subscription;
  late StreamSubscription _trackChangeSubscription;

  late List<VideoTrack> videoTracks;
  late List<AudioTrack> audioTracks;
  late List<SubtitleTrack> subtitleTracks;

  late String selectedVideoTrack;
  late String selectedAudioTrack;
  late String selectedSubtitleTrack;

  @override
  void initState() {
    super.initState();
    _loadTracks();

    subscription = EventBus().on<Tracks>('player_tracks').listen((Tracks data) {
      if (mounted) {
        setState(() {
          videoTracks = data.video;
          audioTracks = data.audio;
          subtitleTracks = data.subtitle;
        });
      }
    });

    _trackChangeSubscription =
        EventBus().on<dynamic>('player_track_changed').listen((_) {
      if (mounted) {
        setState(() {
          selectedVideoTrack = PlayerState.selectedVideo.id;
          selectedAudioTrack = PlayerState.selectedAudio.id;
          selectedSubtitleTrack = PlayerState.selectedSubtitle.id;
        });
      }
    });
  }

  void _loadTracks() {
    videoTracks = PlayerState.videos;
    audioTracks = PlayerState.audios;
    subtitleTracks = PlayerState.subtitles;

    selectedVideoTrack = PlayerState.selectedVideo.id;
    selectedAudioTrack = PlayerState.selectedAudio.id;
    selectedSubtitleTrack = PlayerState.selectedSubtitle.id;
  }

  @override
  void dispose() {
    subscription.cancel();
    _trackChangeSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Colors.black.withOpacity(0.95);

    return Positioned.fill(
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: backgroundColor,
          elevation: 8,
          child: Container(
            width: widget.width,
            height: double.infinity,
            decoration: BoxDecoration(
              color: backgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: _buildMainSettings(context),
          ),
        ),
      ),
    );
  }

  Widget _buildMainSettings(BuildContext context) {
    final cardColor = Colors.black.withOpacity(0.8);
    const textColor = Colors.white;
    final dividerColor = Colors.grey[800]!;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            border: Border(
              bottom: BorderSide(color: dividerColor, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.loc.settings,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: textColor, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTrackSectionGeneric<VideoTrack>(
                  context,
                  icon: Icons.video_settings,
                  title: context.loc.video_track,
                  tracks: videoTracks,
                  labelBuilder: _formatVideoTrack,
                  isSelected: (track) => track.id == selectedVideoTrack,
                  onTrackSelected: (track) {
                    EventBus().emit('video_track_changed', track);
                    if (mounted) {
                      setState(() {
                        selectedVideoTrack = track.id;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildTrackSectionGeneric<AudioTrack>(
                  context,
                  icon: Icons.audiotrack,
                  title: context.loc.audio_track,
                  tracks: audioTracks,
                  labelBuilder: _formatAudioTrack,
                  isSelected: (track) => track.id == selectedAudioTrack,
                  onTrackSelected: (track) {
                    EventBus().emit('audio_track_changed', track);
                    if (mounted) {
                      setState(() {
                        selectedAudioTrack = track.id;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildTrackSectionGeneric<SubtitleTrack>(
                  context,
                  icon: Icons.subtitles,
                  title: context.loc.subtitle_track,
                  tracks: subtitleTracks,
                  labelBuilder: _formatSubtitleTrack,
                  isSelected: (track) => track.id == selectedSubtitleTrack,
                  onTrackSelected: (track) {
                    EventBus().emit('subtitle_track_changed', track);
                    if (mounted) {
                      setState(() {
                        selectedSubtitleTrack = track.id;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackSectionGeneric<T>(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<T> tracks,
    required String Function(T) labelBuilder,
    required Function(T) onTrackSelected,
    required bool Function(T) isSelected,
  }) {
    const textColor = Colors.white;
    const secondaryTextColor = Colors.grey;
    final dividerColor = Colors.grey[800]!;
    const primaryColor = Colors.blue;
    final cardBackground = Colors.white.withOpacity(0.05);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: primaryColor),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
          if (tracks.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...tracks.map((track) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildTrackItem(
                    context,
                    title: labelBuilder(track),
                    isSelected: isSelected(track),
                    onTap: () => onTrackSelected(track),
                  ),
                )),
          ] else
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 8),
              child: Text(
                context.loc.no_tracks_available,
                style: TextStyle(
                  fontSize: 12,
                  color: secondaryTextColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrackItem(
    BuildContext context, {
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    const textColor = Colors.white;
    final dividerColor = Colors.grey[800]!;
    const primaryColor = Colors.blue;
    final primaryContainer = Colors.blue.withOpacity(0.2);
    final unselectedBackground = Colors.white.withOpacity(0.03);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryContainer.withOpacity(0.3)
              : unselectedBackground,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(
                  color: primaryColor,
                  width: 1.5,
                )
              : Border.all(
                  color: dividerColor,
                  width: 0.5,
                ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: textColor,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: primaryColor,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  String _formatVideoTrack(VideoTrack track) {
    if (track.id == 'auto') return 'Auto';
    if (track.id == 'no') return 'Disabled';

    final parts = <String>[];

    if (track.title != null && track.title!.isNotEmpty) {
      parts.add(track.title!);
    }

    if (track.w != null && track.h != null && track.w! > 0 && track.h! > 0) {
      parts.add('${track.w}x${track.h}');
    }

    if (track.fps != null && track.fps! > 0) {
      parts.add('${track.fps!.toStringAsFixed(2)} fps');
    }

    if (track.codec != null && track.codec!.isNotEmpty) {
      parts.add(track.codec!);
    }

    if (track.bitrate != null && track.bitrate! > 0) {
      parts.add('${(track.bitrate! / 1000).round()} kbps');
    }

    if (parts.isEmpty) return 'Track ${track.id}';
    return parts.join(' • ');
  }

  String _formatAudioTrack(AudioTrack track) {
    if (track.id == 'auto') return 'Auto';
    if (track.id == 'no') return 'Disabled';

    final parts = <String>[];

    if (track.title != null && track.title!.isNotEmpty) {
      parts.add(track.title!);
    }

    if (track.language != null && track.language!.isNotEmpty) {
      parts.add(track.language!);
    }

    if (track.codec != null && track.codec!.isNotEmpty) {
      parts.add(track.codec!);
    }

    if (track.channelscount != null && track.channelscount! > 0) {
      parts.add('${track.channelscount}ch');
    }

    if (track.samplerate != null && track.samplerate! > 0) {
      parts.add('${track.samplerate} Hz');
    }

    if (track.bitrate != null && track.bitrate! > 0) {
      parts.add('${(track.bitrate! / 1000).round()} kbps');
    }

    if (parts.isEmpty) return 'Track ${track.id}';
    return parts.join(' • ');
  }

  String _formatSubtitleTrack(SubtitleTrack track) {
    if (track.id == 'auto') return 'Auto';
    if (track.id == 'no') return 'Disabled';

    final parts = <String>[];

    if (track.title != null && track.title!.isNotEmpty) {
      parts.add(track.title!);
    }

    if (track.language != null && track.language!.isNotEmpty) {
      parts.add(track.language!);
    }

    if (track.codec != null && track.codec!.isNotEmpty) {
      parts.add(track.codec!);
    }

    if (parts.isEmpty) return 'Track ${track.id}';
    return parts.join(' • ');
  }
}
