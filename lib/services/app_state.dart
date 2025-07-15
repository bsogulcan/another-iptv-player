import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';
import 'package:another_iptv_player/repositories/m3u_repository.dart';

abstract class AppState {
  static Playlist? currentPlaylist;
  static IptvRepository? xtreamCodeRepository;
  static M3uRepository? m3uRepository;
}
