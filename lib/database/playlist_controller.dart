import 'package:flutter/material.dart';
import 'package:iptv_player/database/database.dart';
import '../models/playlist_model.dart';
import '../services/playlist_service.dart';

class PlaylistController extends ChangeNotifier {
  List<Playlist> _playlists = [];
  bool _isLoading = false;
  String? _error;
  AppDatabase _database = AppDatabase();

  // Getters
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Playlist sayısı
  int get playlistCount => _playlists.length;

  // Tip bazında playlist sayıları
  int get xstreamCount =>
      _playlists.where((p) => p.type == PlaylistType.xstream).length;
  int get m3uCount =>
      _playlists.where((p) => p.type == PlaylistType.m3u).length;

  // Uygulama başlatıldığında çağrılacak
  Future<void> initializeApp() async {
    await loadPlaylists();
  }

  // Tüm playlistleri yükle
  Future<void> loadPlaylists() async {
    _setLoading(true);
    _clearError();

    try {
      _playlists = await PlaylistService.getPlaylists();
      _sortPlaylists();
    } catch (e) {
      _setError('Playlistler yüklenemedi: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  // Yeni playlist oluştur
  Future<Playlist?> createPlaylist({
    required String name,
    required PlaylistType type,
    String? url,
    String? username,
    String? password,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      // Duplicate name kontrolü
      if (_playlists.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
        _setError('Bu isimde bir playlist zaten mevcut');
        return null;
      }

      final playlist = Playlist(
        id: _generateUniqueId(),
        name: name.trim(),
        type: type,
        url: url?.trim(),
        username: username?.trim(),
        password: password?.trim(),
        createdAt: DateTime.now(),
      );

      await PlaylistService.savePlaylist(playlist);
      _playlists.add(playlist);
      _sortPlaylists();

      return playlist;
    } catch (e) {
      _setError('Playlist kaydedilemedi: ${e.toString()}');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  // Playlist sil
  Future<bool> deletePlaylist(String id) async {
    try {
      await PlaylistService.deletePlaylist(id);
      _playlists.removeWhere((playlist) => playlist.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _setError('Playlist silinemedi: ${e.toString()}');
      return false;
    }
  }

  // Playlist güncelle
  Future<bool> updatePlaylist(Playlist updatedPlaylist) async {
    _setLoading(true);
    _clearError();

    try {
      // Aynı isimde başka playlist var mı kontrol et (kendisi hariç)
      if (_playlists.any(
        (p) =>
            p.id != updatedPlaylist.id &&
            p.name.toLowerCase() == updatedPlaylist.name.toLowerCase(),
      )) {
        _setError('Bu isimde bir playlist zaten mevcut');
        return false;
      }

      await PlaylistService.updatePlaylist(updatedPlaylist);

      final index = _playlists.indexWhere((p) => p.id == updatedPlaylist.id);
      if (index != -1) {
        _playlists[index] = updatedPlaylist;
        _sortPlaylists();
      }

      return true;
    } catch (e) {
      _setError('Playlist güncellenemedi: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ID'ye göre playlist getir
  Playlist? getPlaylistById(String id) {
    try {
      return _playlists.firstWhere((playlist) => playlist.id == id);
    } catch (e) {
      return null;
    }
  }

  // Tip bazında filtreleme
  List<Playlist> getPlaylistsByType(PlaylistType type) {
    return _playlists.where((playlist) => playlist.type == type).toList();
  }

  // XStream playlistleri getir
  List<Playlist> get xstreamPlaylists =>
      getPlaylistsByType(PlaylistType.xstream);

  // M3U playlistleri getir
  List<Playlist> get m3uPlaylists => getPlaylistsByType(PlaylistType.m3u);

  // Arama fonksiyonu
  List<Playlist> searchPlaylists(String query) {
    if (query.trim().isEmpty) return _playlists;

    final lowercaseQuery = query.toLowerCase();
    return _playlists
        .where(
          (playlist) =>
              playlist.name.toLowerCase().contains(lowercaseQuery) ||
              (playlist.url?.toLowerCase().contains(lowercaseQuery) ?? false) ||
              (playlist.username?.toLowerCase().contains(lowercaseQuery) ??
                  false),
        )
        .toList();
  }

  // Playlist'i favori olarak işaretle (gelecekte kullanım için)
  Future<bool> toggleFavorite(String id) async {
    // TODO: Favorite özelliği eklenecek
    return true;
  }

  // Playlistleri sırala
  void _sortPlaylists() {
    _playlists.sort(
      (a, b) => b.createdAt.compareTo(a.createdAt),
    ); // Yeniden eskiye
  }

  // Hata temizle
  void clearError() {
    _clearError();
  }

  // Loading durumunu ayarla
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  // Hata durumunu ayarla
  void _setError(String errorMessage) {
    _error = errorMessage;
    _isLoading = false;
    notifyListeners();
  }

  // Hata durumunu temizle
  void _clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  // Benzersiz ID oluştur
  String _generateUniqueId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_playlists.length}';
  }

  // Playlist validasyonu
  bool validatePlaylistData({
    required String name,
    required PlaylistType type,
    String? url,
    String? username,
    String? password,
  }) {
    // İsim kontrolü
    if (name.trim().isEmpty || name.trim().length < 2) {
      return false;
    }

    // XStream için ekstra kontroller
    if (type == PlaylistType.xstream) {
      if (url?.trim().isEmpty ?? true) return false;
      if (username?.trim().isEmpty ?? true) return false;
      if (password?.trim().isEmpty ?? true) return false;

      // URL format kontrolü
      final uri = Uri.tryParse(url!.trim());
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        return false;
      }
    }

    return true;
  }

  // Debug bilgileri
  Map<String, dynamic> getDebugInfo() {
    return {
      'totalPlaylists': _playlists.length,
      'xstreamCount': xstreamCount,
      'm3uCount': m3uCount,
      'isLoading': _isLoading,
      'hasError': _error != null,
      'errorMessage': _error,
      'playlistIds': _playlists.map((p) => p.id).toList(),
    };
  }

  // Bulk operations (toplu işlemler)
  Future<bool> deleteMultiplePlaylists(List<String> ids) async {
    _setLoading(true);
    _clearError();

    try {
      for (String id in ids) {
        await PlaylistService.deletePlaylist(id);
        _playlists.removeWhere((playlist) => playlist.id == id);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _setError('Playlistler silinemedi: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Export playlists (gelecekte kullanım için)
  Future<String> exportPlaylistsAsJson() async {
    try {
      final playlistData = _playlists.map((p) => p.toJson()).toList();
      return playlistData.toString(); // JSON encode edilecek
    } catch (e) {
      throw Exception('Export işlemi başarısız: ${e.toString()}');
    }
  }

  // Import playlists (gelecekte kullanım için)
  Future<bool> importPlaylistsFromJson(String jsonData) async {
    // TODO: JSON import özelliği eklenecek
    return true;
  }

  // Verileri yenile (pull-to-refresh için)
  Future<void> refreshPlaylists() async {
    await loadPlaylists();
  }

  // Controller'ı temizle
  @override
  void dispose() {
    _playlists.clear();
    super.dispose();
  }

  // Playlist istatistikleri
  Map<String, int> getPlaylistStats() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisWeek = now.subtract(Duration(days: 7));
    final thisMonth = DateTime(now.year, now.month, 1);

    return {
      'total': _playlists.length,
      'xstream': xstreamCount,
      'm3u': m3uCount,
      'createdToday': _playlists.where((p) {
        final playlistDate = DateTime(
          p.createdAt.year,
          p.createdAt.month,
          p.createdAt.day,
        );
        return playlistDate.isAtSameMomentAs(today);
      }).length,
      'createdThisWeek': _playlists
          .where((p) => p.createdAt.isAfter(thisWeek))
          .length,
      'createdThisMonth': _playlists
          .where((p) => p.createdAt.isAfter(thisMonth))
          .length,
    };
  }
}
