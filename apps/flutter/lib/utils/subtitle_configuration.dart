import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:flutter/cupertino.dart';
import 'package:media_kit_video/media_kit_video.dart';

Future<SubtitleViewConfiguration> getSubtitleConfiguration() async {
  return SubtitleViewConfiguration(
    style: TextStyle(
      height: await UserPreferences.getSubtitleHeight(),
      fontSize: await UserPreferences.getSubtitleFontSize(),
      letterSpacing: await UserPreferences.getSubtitleLetterSpacing(),
      wordSpacing: await UserPreferences.getSubtitleWordSpacing(),
      color: await UserPreferences.getSubtitleTextColor(),
      fontWeight: await UserPreferences.getSubtitleFontWeight(),
      backgroundColor: await UserPreferences.getSubtitleBackgroundColor(),
    ),
    textAlign: await UserPreferences.getSubtitleTextAlign(),
    padding: EdgeInsets.all(await UserPreferences.getSubtitlePadding()),
  );
}
