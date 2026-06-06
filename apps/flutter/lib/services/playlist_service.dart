import '../models/playlist_model.dart';
import 'database_service.dart';

class PlaylistService {
  static Future<void> savePlaylist(Playlist playlist) async {
    await DatabaseService.savePlaylist(playlist);
  }

  static Future<List<Playlist>> getPlaylists() async {
    return await DatabaseService.getPlaylists();
  }

  static Future<void> deletePlaylist(String id) async {
    await DatabaseService.deletePlaylist(id);
  }

  static Future<void> updatePlaylist(Playlist playlist) async {
    await DatabaseService.updatePlaylist(playlist);
  }

  static Future<Playlist?> getPlaylistById(String id) async {
    return await DatabaseService.getPlaylistById(id);
  }

  static Future<List<Playlist>> getXStreamPlaylists() async {
    return await DatabaseService.getPlaylistsByType(PlaylistType.xtream);
  }

  static Future<List<Playlist>> getM3UPlaylists() async {
    return await DatabaseService.getPlaylistsByType(PlaylistType.m3u);
  }
}