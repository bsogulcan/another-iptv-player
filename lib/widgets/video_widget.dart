import 'package:another_iptv_player/services/player_state.dart';
import 'package:another_iptv_player/widgets/player-buttons/back_button_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_settings_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_title_widget.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

// Helper function to get the current stream URL
String _getCurrentStreamUrl() {
  // Use the same URL that the player is actually opening
  final content = PlayerState.currentContent;
  return content?.url ?? '';
}

Widget getVideo(
    BuildContext context,
    VideoController controller,
    SubtitleViewConfiguration subtitleViewConfiguration,
    ) {

  switch (Theme.of(context).platform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return MaterialVideoControlsTheme(
        normal: MaterialVideoControlsThemeData().copyWith(
          brightnessGesture: false,
          volumeGesture: false,
          seekGesture: false,
          speedUpOnLongPress: true,
          seekOnDoubleTap: true,
          topButtonBar: [
            BackButtonWidget(),
            Expanded(child: VideoTitleWidget()),
            VideoSettingsWidget(streamUrl: streamUrl),
          ],
        ),
        fullscreen: MaterialVideoControlsThemeData().copyWith(
          brightnessGesture: false,
          volumeGesture: false,
          seekGesture: false,
          speedUpOnLongPress: true,
          seekOnDoubleTap: true,
          topButtonBar: [
            BackButtonWidget(),
            Expanded(child: VideoTitleWidget()),
            VideoSettingsWidget(streamUrl: streamUrl),
          ],
          seekBarMargin: EdgeInsets.fromLTRB(0, 0, 0, 10),
        ),
        child: Scaffold(
          body: Video(
            controller: controller,
            resumeUponEnteringForegroundMode: true,
            pauseUponEnteringBackgroundMode: !PlayerState.backgroundPlay,
            subtitleViewConfiguration: subtitleViewConfiguration,
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
            VideoSettingsWidget(streamUrl: streamUrl),
          ],
        ),
        fullscreen: MaterialDesktopVideoControlsThemeData().copyWith(
          modifyVolumeOnScroll: false,
          toggleFullscreenOnDoublePress: true,
          topButtonBar: [
            BackButtonWidget(),
            Expanded(child: VideoTitleWidget()),
            VideoSettingsWidget(streamUrl: streamUrl),
          ],
        ),
        child: Scaffold(
          body: Video(
            controller: controller,
            resumeUponEnteringForegroundMode: true,
            pauseUponEnteringBackgroundMode: !PlayerState.backgroundPlay,
            subtitleViewConfiguration: subtitleViewConfiguration,
          ),
        ),
      );
    default:
      return Video(
        controller: controller,
        controls: NoVideoControls,
        resumeUponEnteringForegroundMode: true,
        pauseUponEnteringBackgroundMode: !PlayerState.backgroundPlay,
        subtitleViewConfiguration: subtitleViewConfiguration,
      );
  }
}