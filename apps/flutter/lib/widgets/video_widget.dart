import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/services/player_state.dart';
import 'package:another_iptv_player/widgets/player-buttons/back_button_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_channel_selector_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_favorite_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_info_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_settings_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_title_widget.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoWidget extends StatefulWidget {
  final VideoController controller;
  final SubtitleViewConfiguration subtitleViewConfiguration;

  const VideoWidget({
    super.key,
    required this.controller,
    required this.subtitleViewConfiguration,
  });

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  bool _brightnessGesture = false;
  bool _volumeGesture = false;
  bool _seekGesture = false;
  bool _speedUpOnLongPress = true;
  bool _seekOnDoubleTap = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final brightnessGesture = await UserPreferences.getBrightnessGesture();
    final volumeGesture = await UserPreferences.getVolumeGesture();
    final seekGesture = await UserPreferences.getSeekGesture();
    final speedUpOnLongPress = await UserPreferences.getSpeedUpOnLongPress();
    final seekOnDoubleTap = await UserPreferences.getSeekOnDoubleTap();
    if (mounted) {
      setState(() {
        _brightnessGesture = brightnessGesture;
        _volumeGesture = volumeGesture;
        _seekGesture = seekGesture;
        _speedUpOnLongPress = speedUpOnLongPress;
        _seekOnDoubleTap = seekOnDoubleTap;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return MaterialVideoControlsTheme(
          normal: MaterialVideoControlsThemeData().copyWith(
            brightnessGesture: _brightnessGesture,
            volumeGesture: _volumeGesture,
            seekGesture: _seekGesture,
            speedUpOnLongPress: _speedUpOnLongPress,
            seekOnDoubleTap: _seekOnDoubleTap,
            topButtonBar: [
            BackButtonWidget(),
            Expanded(child: VideoTitleWidget()),
            VideoInfoWidget(),
            VideoChannelSelectorWidget(
              queue: PlayerState.queue,
              currentIndex: PlayerState.currentIndex,
            ),
            VideoFavoriteWidget(),
            VideoSettingsWidget(),
          ],
          bottomButtonBar: const [MaterialPositionIndicator()],
        ),
        fullscreen: MaterialVideoControlsThemeData().copyWith(
          brightnessGesture: _brightnessGesture,
          volumeGesture: _volumeGesture,
          seekGesture: _seekGesture,
          speedUpOnLongPress: _speedUpOnLongPress,
          seekOnDoubleTap: _seekOnDoubleTap,
          topButtonBar: [
            BackButtonWidget(),
            Expanded(child: VideoTitleWidget()),
            VideoInfoWidget(),
            VideoChannelSelectorWidget(
              queue: PlayerState.queue,
              currentIndex: PlayerState.currentIndex,
            ),
            VideoFavoriteWidget(),
            VideoSettingsWidget(),
          ],
          seekBarMargin: EdgeInsets.fromLTRB(0, 0, 0, 10),
        ),
        child: Scaffold(
          body: Video(
            controller: widget.controller,
            resumeUponEnteringForegroundMode: true,
            pauseUponEnteringBackgroundMode: !PlayerState.backgroundPlay,
            subtitleViewConfiguration: widget.subtitleViewConfiguration,
          ),
        ),
      );
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return MaterialDesktopVideoControlsTheme(
          normal: MaterialDesktopVideoControlsThemeData().copyWith(
            modifyVolumeOnScroll: false,
            toggleFullscreenOnDoublePress: true,
            topButtonBar: [
              BackButtonWidget(),
              Expanded(child: VideoTitleWidget()),
              VideoInfoWidget(),
              VideoChannelSelectorWidget(
                queue: PlayerState.queue,
                currentIndex: PlayerState.currentIndex,
              ),
              VideoFavoriteWidget(),
              VideoSettingsWidget(),
            ],
          ),
          fullscreen: MaterialDesktopVideoControlsThemeData().copyWith(
            modifyVolumeOnScroll: false,
            toggleFullscreenOnDoublePress: true,
            topButtonBar: [
              BackButtonWidget(),
              Expanded(child: VideoTitleWidget()),
              VideoInfoWidget(),
              VideoChannelSelectorWidget(
                queue: PlayerState.queue,
                currentIndex: PlayerState.currentIndex,
              ),
              VideoFavoriteWidget(),
              VideoSettingsWidget(),
            ],
          ),
          child: Scaffold(
            body: Video(
              controller: widget.controller,
              resumeUponEnteringForegroundMode: true,
              pauseUponEnteringBackgroundMode: !PlayerState.backgroundPlay,
              subtitleViewConfiguration: widget.subtitleViewConfiguration,
            ),
          ),
        );
      default:
        return Video(
          controller: widget.controller,
          controls: NoVideoControls,
          resumeUponEnteringForegroundMode: true,
          pauseUponEnteringBackgroundMode: !PlayerState.backgroundPlay,
          subtitleViewConfiguration: widget.subtitleViewConfiguration,
        );
    }
  }
}

// Backward compatibility wrapper
Widget getVideo(
  BuildContext context,
  VideoController controller,
  SubtitleViewConfiguration subtitleViewConfiguration,
) {
  return VideoWidget(
    controller: controller,
    subtitleViewConfiguration: subtitleViewConfiguration,
  );
}
