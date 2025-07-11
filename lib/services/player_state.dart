import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

abstract class PlayerState {
  static List<VideoTrack> videos = [];
  static VideoTrack selectedVideo = VideoTrack.auto();

  static List<AudioTrack> audios = [];
  static AudioTrack selectedAudio = AudioTrack.auto();

  static List<SubtitleTrack> subtitles = [];
  static SubtitleTrack selectedSubtitle = SubtitleTrack.auto();

  static String title = '';
  static bool backgroundPlay = true;
  static SubtitleViewConfiguration subtitleConfiguration =
      SubtitleViewConfiguration();
}
