import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <-- added for Clipboard
import 'package:another_iptv_player/services/event_bus.dart';
import 'package:another_iptv_player/services/player_state.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;

class VideoSettingsWidget extends StatefulWidget {
  const VideoSettingsWidget({super.key});

  @override
  State<VideoSettingsWidget> createState() => _VideoSettingsWidgetState();
}

class _VideoSettingsWidgetState extends State<VideoSettingsWidget> {
  late StreamSubscription subscription;
  late List<VideoTrack> videoTracks;
  late List<AudioTrack> audioTracks;
  late List<SubtitleTrack> subtitleTracks;

  late String selectedVideoTrack;
  late String selectedAudioTrack;
  late String selectedSubtitleTrack;

  @override
  void initState() {
    super.initState();

    videoTracks = PlayerState.videos;
    audioTracks = PlayerState.audios;
    subtitleTracks = PlayerState.subtitles;

    selectedVideoTrack = PlayerState.selectedVideo.title ?? 'Empty';
    selectedAudioTrack = PlayerState.selectedAudio.language ?? 'Empty';
    selectedSubtitleTrack = PlayerState.selectedSubtitle.language ?? 'Empty';

    subscription = EventBus().on<Tracks>('player_tracks').listen((Tracks data) {
      if (mounted) {
        setState(() {
          videoTracks = data.video;
          audioTracks = data.audio;
          subtitleTracks = data.subtitle;
        });
      }
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.settings, color: Colors.white),
      onPressed: () => _showSettingsBottomSheet(context),
    );
  }

  void _showSettingsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
        minHeight: MediaQuery.of(context).size.height * 0.3,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Text(
                context.loc.settings,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 20),
              _buildSettingsItem(
                icon: Icons.video_settings,
                title: context.loc.video_track,
                subtitle: selectedVideoTrack,
                onTap: () => _showVideoTrackSelection(context),
              ),
              _buildSettingsItem(
                icon: Icons.audiotrack,
                title: context.loc.audio_track,
                subtitle: selectedAudioTrack,
                onTap: () => _showAudioTrackSelection(context),
              ),
              _buildSettingsItem(
                icon: Icons.subtitles,
                title: context.loc.subtitle_track,
                subtitle: selectedSubtitleTrack,
                onTap: () => _showSubtitleTrackSelection(context),
              ),

              // Copy Stream URL action: compute URL at tap time so it's always fresh
              ListTile(
                leading: const Icon(Icons.link, color: Colors.blue),
                title: const Text('Copy stream URL'),
                onTap: () async {
                  final url = PlayerState.currentContent?.url ?? '';

                  if (url.isEmpty) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No stream URL available'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }

                  await Clipboard.setData(ClipboardData(text: url));

                  if (!context.mounted) return;

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Stream URL copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              // -----------------------------------

              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  void _showVideoTrackSelection(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
        minHeight: MediaQuery.of(context).size.height * 0.3,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back),
                    onPressed: () {
                      Navigator.pop(context);
                      _showSettingsBottomSheet(context);
                    },
                  ),
                  Text(
                    context.loc.quality,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: videoTracks
                        .map(
                          (track) => ListTile(
                        title: Text(track.id),
                        trailing: selectedVideoTrack == track.id
                            ? Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () {
                          EventBus().emit('video_track_changed', track);

                          if (mounted) {
                            setState(() {
                              selectedVideoTrack = track.id;
                            });
                          }
                          Navigator.pop(context);
                        },
                      ),
                    )
                        .toList(),
                  ),
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showAudioTrackSelection(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
        minHeight: MediaQuery.of(context).size.height * 0.3,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back),
                    onPressed: () {
                      Navigator.pop(context);
                      _showSettingsBottomSheet(context);
                    },
                  ),
                  Text(
                    context.loc.audio_track,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: audioTracks
                        .map(
                          (track) => ListTile(
                        title: Text(track.language ?? 'NULL'),
                        trailing:
                        selectedAudioTrack == (track.language ?? 'NULL')
                            ? Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () {
                          EventBus().emit('audio_track_changed', track);

                          if (mounted) {
                            setState(() {
                              selectedAudioTrack = track.language ?? 'NULL';
                            });
                          }
                          Navigator.pop(context);
                        },
                      ),
                    )
                        .toList(),
                  ),
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showSubtitleTrackSelection(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
        minHeight: MediaQuery.of(context).size.height * 0.3,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back),
                    onPressed: () {
                      Navigator.pop(context);
                      _showSettingsBottomSheet(context);
                    },
                  ),
                  Text(
                    context.loc.subtitle_track,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: subtitleTracks
                        .map(
                          (track) => ListTile(
                        title: Text(track.language ?? 'NULL'),
                        trailing:
                        selectedSubtitleTrack ==
                            (track.language ?? 'NULL')
                            ? Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () {
                          EventBus().emit('subtitle_track_changed', track);

                          if (mounted) {
                            setState(() {
                              selectedSubtitleTrack =
                                  track.language ?? 'NULL';
                            });
                          }
                          Navigator.pop(context);
                        },
                      ),
                    )
                        .toList(),
                  ),
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}