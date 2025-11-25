import 'package:another_iptv_player/services/player_state.dart';
import 'package:another_iptv_player/widgets/player-buttons/back_button_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_settings_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_title_widget.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
            VideoSettingsWidget(),
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
            VideoSettingsWidget(),
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
            VideoSettingsWidget(),
          ],
        ),
        fullscreen: MaterialDesktopVideoControlsThemeData().copyWith(
          modifyVolumeOnScroll: false,
          toggleFullscreenOnDoublePress: true,
          topButtonBar: [
            BackButtonWidget(),
            Expanded(child: VideoTitleWidget()),
            VideoSettingsWidget(),
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