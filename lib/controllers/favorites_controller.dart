import 'package:flutter/foundation.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/favorite.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/repositories/favorites_repository.dart';

class FavoritesController extends ChangeNotifier {
  final FavoritesRepository _repository = FavoritesRepository();
  
  List<Favorite> _favorites = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  List<Favorite> get favorites => _favorites;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  // Canlı yayın favorileri
  List<Favorite> get liveStreamFavorites => 
      _favorites.where((f) => f.contentType == ContentType.liveStream).toList();
  
  // Film favorileri
  List<Favorite> get movieFavorites => 
      _favorites.where((f) => f.contentType == ContentType.vod).toList();
  
  // Dizi favorileri
  List<Favorite> get seriesFavorites => 
      _favorites.where((f) => f.contentType == ContentType.series).toList();

  // Favori sayıları
  int get totalFavoriteCount => _favorites.length;
  int get liveStreamFavoriteCount => liveStreamFavorites.length;
  int get movieFavoriteCount => movieFavorites.length;
  int get seriesFavoriteCount => seriesFavorites.length;

  // Favorileri yükle
  Future<void> loadFavorites() async {
    print('FavoritesController: loadFavorites başladı');
    try {
      _setLoading(true);
      _setError(null);
      
      // Mevcut favorileri temizle
      _favorites.clear();
      notifyListeners();
      
      _favorites = await _repository.getAllFavorites();
      print('FavoritesController: ${_favorites.length} favori yüklendi');
      notifyListeners();
    } catch (e) {
      print('FavoritesController: Hata: $e');
      _setError('Favoriler yüklenirken hata oluştu: $e');
    } finally {
      _setLoading(false);
    }
  }

  // Favori ekle
  Future<bool> addFavorite(ContentItem contentItem) async {
    try {
      _setError(null);
      
      await _repository.addFavorite(contentItem);
      // Hızlı güncelleme için listeyi yenile
      await loadFavorites();
      
      return true;
    } catch (e) {
      _setError('Favori eklenirken hata oluştu: $e');
      return false;
    }
  }

  // Favori kaldır
  Future<bool> removeFavorite(String streamId, ContentType contentType, {String? episodeId}) async {
    try {
      _setError(null);
      
      await _repository.removeFavorite(streamId, contentType, episodeId: episodeId);
      // Hızlı güncelleme için listeyi yenile
      await loadFavorites();
      
      return true;
    } catch (e) {
      _setError('Favori kaldırılırken hata oluştu: $e');
      return false;
    }
  }

  // Favori toggle (ekle/kaldır)
  Future<bool> toggleFavorite(ContentItem contentItem) async {
    try {
      _setError(null);
      
      final result = await _repository.toggleFavorite(contentItem);
      // Hızlı güncelleme için listeyi yenile
      await loadFavorites();
      
      return result;
    } catch (e) {
      _setError('Favori işlemi sırasında hata oluştu: $e');
      return false;
    }
  }

  // Favori var mı kontrol et
  Future<bool> isFavorite(String streamId, ContentType contentType, {String? episodeId}) async {
    try {
      return await _repository.isFavorite(streamId, contentType, episodeId: episodeId);
    } catch (e) {
      _setError('Favori kontrolü sırasında hata oluştu: $e');
      return false;
    }
  }

  // İçerik tipine göre favorileri getir
  Future<List<Favorite>> getFavoritesByContentType(ContentType contentType) async {
    try {
      return await _repository.getFavoritesByContentType(contentType);
    } catch (e) {
      _setError('Favoriler getirilirken hata oluştu: $e');
      return [];
    }
  }

  // Favori sayısını getir
  Future<int> getFavoriteCount() async {
    try {
      return await _repository.getFavoriteCount();
    } catch (e) {
      _setError('Favori sayısı getirilirken hata oluştu: $e');
      return 0;
    }
  }

  // İçerik tipine göre favori sayısını getir
  Future<int> getFavoriteCountByContentType(ContentType contentType) async {
    try {
      return await _repository.getFavoriteCountByContentType(contentType);
    } catch (e) {
      _setError('Favori sayısı getirilirken hata oluştu: $e');
      return 0;
    }
  }

  // Favori güncelle
  Future<bool> updateFavorite(Favorite favorite) async {
    try {
      _setError(null);
      
      await _repository.updateFavorite(favorite);
      // Hızlı güncelleme için listeyi yenile
      await loadFavorites();
      
      return true;
    } catch (e) {
      _setError('Favori güncellenirken hata oluştu: $e');
      return false;
    }
  }

  // Tüm favorileri temizle
  Future<bool> clearAllFavorites() async {
    try {
      _setError(null);
      
      await _repository.clearAllFavorites();
      _favorites.clear();
      notifyListeners();
      
      return true;
    } catch (e) {
      _setError('Favoriler temizlenirken hata oluştu: $e');
      return false;
    }
  }

  // Favori ara
  List<Favorite> searchFavorites(String query) {
    if (query.isEmpty) return _favorites;
    
    return _favorites.where((favorite) =>
        favorite.name.toLowerCase().contains(query.toLowerCase())).toList();
  }

  // Favori filtrele (içerik tipine göre)
  List<Favorite> filterFavoritesByContentType(ContentType contentType) {
    return _favorites.where((favorite) => favorite.contentType == contentType).toList();
  }

  // Hata temizle
  void clearError() {
    _setError(null);
  }

  // Loading durumunu ayarla
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Hata ayarla
  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }
} 