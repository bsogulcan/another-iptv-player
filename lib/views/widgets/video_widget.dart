import 'package:flutter/material.dart';
import 'package:iptv_player/services/player_state.dart';
import 'package:iptv_player/views/widgets/player-buttons/back_button_widget.dart';
import 'package:iptv_player/views/widgets/player-buttons/video_settings_widget.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../utils/helpers.dart' as UniversalPlatform;

Widget getVideo(BuildContext context, VideoController controller, Key key) {
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
            Text(PlayerState.title),
            Spacer(),
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
            Text(PlayerState.title),
            Spacer(),
            VideoSettingsWidget(),
          ],
        ),
        child: Scaffold(
          body: Video(
            controller: controller!,
            key: key,
            onEnterFullscreen: () async {
              await defaultEnterNativeFullscreen();
            },
            onExitFullscreen: () async {
              await defaultExitNativeFullscreen();
              if (!UniversalPlatform.isDesktop) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
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
            Text(PlayerState.title),
            Spacer(),
            VideoSettingsWidget(),
          ],
        ),
        fullscreen: MaterialDesktopVideoControlsThemeData().copyWith(
          modifyVolumeOnScroll: false,
          toggleFullscreenOnDoublePress: true,
          topButtonBar: [
            BackButtonWidget(),
            Text(PlayerState.title),
            Spacer(),
            VideoSettingsWidget(),
          ],
        ),
        child: Scaffold(
          body: Video(
            controller: controller!,
            key: key,
            onEnterFullscreen: () async {
              await defaultEnterNativeFullscreen();
            },
            onExitFullscreen: () async {
              await defaultExitNativeFullscreen();
              if (!UniversalPlatform.isDesktop) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
        ),
      );
    default:
      return Video(controller: controller!, controls: NoVideoControls);
  }
}
