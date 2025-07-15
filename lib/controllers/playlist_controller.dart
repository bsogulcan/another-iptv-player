import 'package:another_iptv_player/screens/m3u/m3u_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/services/app_state.dart';
import '../models/playlist_model.dart';
import '../screens/xtream-codes/xtream_code_home_screen.dart';
import '../services/playlist_service.dart';

class PlaylistController extends ChangeNotifier {
  List<Playlist> _playlists = [];
  bool _isLoading = false;
  String? _error;
  bool _hasInitialized = false;

  List<Playlist> get playlists => List.unmodifiable(_playlists);

  bool get isLoading => _isLoading;

  String? get error => _error;

  bool get hasInitialized => _hasInitialized;

  int get playlistCount => _playlists.length;

  int get xtreamCount =>
      _playlists.where((p) => p.type == PlaylistType.xtream).length;

  int get m3uCount =>
      _playlists.where((p) => p.type == PlaylistType.m3u).length;

  List<Playlist> get xtreamPlaylists => getPlaylistsByType(PlaylistType.xtream);

  List<Playlist> get m3uPlaylists => getPlaylistsByType(PlaylistType.m3u);

  Future<void> loadPlaylists(BuildContext context) async {
    _setLoading(true);
    _clearError();

    try {
      _playlists = await PlaylistService.getPlaylists();
      _sortPlaylists();
    } catch (e) {
      setError('Playlistler yüklenemedi: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> openPlaylist(BuildContext context, Playlist playlist) async {
    await UserPreferences.setLastPlaylist(playlist.id);
    AppState.currentPlaylist = playlist;

    if (context.mounted) {
      switch (playlist.type) {
        case PlaylistType.xtream:
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => XtreamCodeHomeScreen(playlist: playlist),
            ),
          );
        case PlaylistType.m3u:
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => M3UHomeScreen(playlist: playlist),
            ),
          );
      }
    }
  }

  Future<Playlist?> createPlaylist({
    required String name,
    required PlaylistType type,
    String? url,
    String? username,
    String? password,
  }) async {
    if (!_validateInput(name, type, url, username, password)) {
      return null;
    }

    _setLoading(true);
    _clearError();

    try {
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
      setError('Playlist kaydedilemedi: ${e.toString()}');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deletePlaylist(String id) async {
    try {
      await PlaylistService.deletePlaylist(id);
      _playlists.removeWhere((playlist) => playlist.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      setError('Playlist silinemedi: ${e.toString()}');
      return false;
    }
  }

  Future<bool> deleteMultiplePlaylists(List<String> ids) async {
    _setLoading(true);
    _clearError();

    try {
      for (final id in ids) {
        await PlaylistService.deletePlaylist(id);
        _playlists.removeWhere((playlist) => playlist.id == id);
      }
      notifyListeners();
      return true;
    } catch (e) {
      setError('Playlistler silinemedi: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updatePlaylist(Playlist updatedPlaylist) async {
    _setLoading(true);
    _clearError();

    try {
      if (_isDuplicateName(updatedPlaylist)) {
        setError('Bu isimde bir playlist zaten mevcut');
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
      setError('Playlist güncellenemedi: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Playlist? getPlaylistById(String id) {
    try {
      return _playlists.firstWhere((playlist) => playlist.id == id);
    } catch (e) {
      return null;
    }
  }

  List<Playlist> getPlaylistsByType(PlaylistType type) {
    return _playlists.where((playlist) => playlist.type == type).toList();
  }

  List<Playlist> searchPlaylists(String query) {
    if (query.trim().isEmpty) return _playlists;

    final lowercaseQuery = query.toLowerCase();
    return _playlists.where((playlist) {
      return playlist.name.toLowerCase().contains(lowercaseQuery) ||
          (playlist.url?.toLowerCase().contains(lowercaseQuery) ?? false) ||
          (playlist.username?.toLowerCase().contains(lowercaseQuery) ?? false);
    }).toList();
  }

  Map<String, int> getPlaylistStats() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisWeek = now.subtract(const Duration(days: 7));
    final thisMonth = DateTime(now.year, now.month, 1);

    return {
      'total': _playlists.length,
      'xstream': xtreamCount,
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

  Future<String> exportPlaylistsAsJson() async {
    try {
      final playlistData = _playlists.map((p) => p.toJson()).toList();
      return playlistData.toString();
    } catch (e) {
      throw Exception('Export işlemi başarısız: ${e.toString()}');
    }
  }

  bool validatePlaylistData({
    required String name,
    required PlaylistType type,
    String? url,
    String? username,
    String? password,
  }) {
    return _validateInput(name, type, url, username, password);
  }

  void clearError() => _clearError();

  Future<void> refreshPlaylists(BuildContext context) async {
    await loadPlaylists(context);
  }

  bool _validateInput(
    String name,
    PlaylistType type,
    String? url,
    String? username,
    String? password,
  ) {
    if (name.trim().isEmpty || name.trim().length < 2) {
      setError('Playlist adı en az 2 karakter olmalıdır');
      return false;
    }

    if (_playlists.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
      setError('Bu isimde bir playlist zaten mevcut');
      return false;
    }

    if (type == PlaylistType.xtream) {
      if (url?.trim().isEmpty ?? true) {
        setError('URL gereklidir');
        return false;
      }
      if (username?.trim().isEmpty ?? true) {
        setError('Kullanıcı adı gereklidir');
        return false;
      }
      if (password?.trim().isEmpty ?? true) {
        setError('Şifre gereklidir');
        return false;
      }

      final uri = Uri.tryParse(url!.trim());
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        setError('Geçerli bir URL giriniz');
        return false;
      }
    }

    return true;
  }

  bool _isDuplicateName(Playlist playlist) {
    return _playlists.any(
      (p) =>
          p.id != playlist.id &&
          p.name.toLowerCase() == playlist.name.toLowerCase(),
    );
  }

  void _sortPlaylists() {
    _playlists.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void setError(String errorMessage) {
    _error = errorMessage;
    _isLoading = false;
    notifyListeners();
  }

  void _clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  String _generateUniqueId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_playlists.length}';
  }

  @override
  void dispose() {
    _playlists.clear();
    super.dispose();
  }
}
