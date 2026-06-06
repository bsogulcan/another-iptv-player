import 'package:another_iptv_player/services/service_locator.dart';

import '../database/database.dart';
import '../models/playlist_model.dart';

class DatabaseService {
  // static final AppDatabase _database = AppDatabase();
  static final _database = getIt<AppDatabase>();

  static AppDatabase get database => _database;

  // Playlist kaydet
  static Future<void> savePlaylist(Playlist playlist) async {
    await _database.insertPlaylist(playlist);
  }

  // Tüm playlistleri getir
  static Future<List<Playlist>> getPlaylists() async {
    return await _database.getAllPlaylists();
  }

  // Playlist sil
  static Future<void> deletePlaylist(String id) async {
    await _database.deletePlaylistById(id);
  }

  // Playlist güncelle
  static Future<void> updatePlaylist(Playlist playlist) async {
    await _database.updatePlaylist(playlist);
  }

  // ID'ye göre playlist getir
  static Future<Playlist?> getPlaylistById(String id) async {
    return await _database.getPlaylistById(id);
  }

  // Tip filtreleme
  static Future<List<Playlist>> getPlaylistsByType(PlaylistType type) async {
    return await _database.getPlaylistsByType(type);
  }

  // Veritabanını kapat
  static Future<void> close() async {
    await _database.close();
  }
}
