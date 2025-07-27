import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/favorite.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/service_locator.dart';
import 'package:another_iptv_player/utils/get_playlist_type.dart';
import 'package:another_iptv_player/repositories/m3u_repository.dart';
import 'package:uuid/uuid.dart';

class FavoritesRepository {
  final _database = getIt<AppDatabase>();
  final _uuid = Uuid();

  FavoritesRepository();

  // Favori ekle
  Future<void> addFavorite(ContentItem contentItem) async {
    final playlistId = AppState.currentPlaylist!.id;

    // Önce favori var mı kontrol et
    final isAlreadyFavorite = await _database.isFavorite(
      playlistId,
      contentItem.id,
      contentItem.contentType,
      contentItem.season != null ? contentItem.id : null, // Episode ID için
    );

    if (isAlreadyFavorite) {
      throw Exception('Bu içerik zaten favorilerde');
    }

    final favorite = Favorite(
      id: _uuid.v4(),
      playlistId: playlistId,
      contentType: contentItem.contentType,
      streamId: contentItem.id,
      // episodeId: contentItem.contentType == ContentType.series
      //     ? contentItem.id
      //     : null,
      m3uItemId: contentItem.m3uItem?.id,
      name: contentItem.name,
      imagePath: contentItem.imagePath,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _database.insertFavorite(favorite);
  }

  // Favori kaldır
  Future<void> removeFavorite(
    String streamId,
    ContentType contentType, {
    String? episodeId,
  }) async {
    final playlistId = AppState.currentPlaylist!.id;

    // Favoriyi bul
    final favorites = await _database.getFavoritesByPlaylist(playlistId);
    final favorite = favorites.firstWhere(
      (f) =>
          f.streamId == streamId &&
          f.contentType == contentType &&
          f.episodeId == episodeId,
      orElse: () => throw Exception('Favori bulunamadı'),
    );

    await _database.deleteFavorite(favorite.id);
  }

  // Favori var mı kontrol et
  Future<bool> isFavorite(
    String streamId,
    ContentType contentType, {
    String? episodeId,
  }) async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.isFavorite(
      playlistId,
      streamId,
      contentType,
      episodeId,
    );
  }

  // Tüm favorileri getir
  Future<List<Favorite>> getAllFavorites() async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.getFavoritesByPlaylist(playlistId);
  }

  // İçerik tipine göre favorileri getir
  Future<List<Favorite>> getFavoritesByContentType(
    ContentType contentType,
  ) async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.getFavoritesByContentType(playlistId, contentType);
  }

  // Canlı yayın favorilerini getir
  Future<List<Favorite>> getLiveStreamFavorites() async {
    return await getFavoritesByContentType(ContentType.liveStream);
  }

  // Film favorilerini getir
  Future<List<Favorite>> getMovieFavorites() async {
    return await getFavoritesByContentType(ContentType.vod);
  }

  // Dizi favorilerini getir
  Future<List<Favorite>> getSeriesFavorites() async {
    return await getFavoritesByContentType(ContentType.series);
  }

  // Favori sayısını getir
  Future<int> getFavoriteCount() async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.getFavoriteCount(playlistId);
  }

  // İçerik tipine göre favori sayısını getir
  Future<int> getFavoriteCountByContentType(ContentType contentType) async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.getFavoriteCountByContentType(
      playlistId,
      contentType,
    );
  }

  // Favori toggle (ekle/kaldır)
  Future<bool> toggleFavorite(ContentItem contentItem) async {
    final playlistId = AppState.currentPlaylist!.id;
    final isCurrentlyFavorite = await _database.isFavorite(
      playlistId,
      contentItem.id,
      contentItem.contentType,
      contentItem.contentType == ContentType.series ? contentItem.id : null,
    );

    if (isCurrentlyFavorite) {
      await removeFavorite(
        contentItem.id,
        contentItem.contentType,
        episodeId: contentItem.contentType == ContentType.series
            ? contentItem.id
            : null,
      );
      return false; // Favorilerden kaldırıldı
    } else {
      await addFavorite(contentItem);
      return true; // Favorilere eklendi
    }
  }

  // Favori güncelle
  Future<void> updateFavorite(Favorite favorite) async {
    await _database.updateFavorite(favorite);
  }

  // Tüm favorileri sil (playlist değiştiğinde)
  Future<void> clearAllFavorites() async {
    final playlistId = AppState.currentPlaylist!.id;
    final favorites = await _database.getFavoritesByPlaylist(playlistId);

    for (final favorite in favorites) {
      await _database.deleteFavorite(favorite.id);
    }
  }

  Future<ContentItem?> getContentItemFromFavorite(Favorite favorite) async {
    try {
      if (isXtreamCode) {
        final repository = AppState.xtreamCodeRepository!;

        switch (favorite.contentType) {
          case ContentType.liveStream:
            final liveStream = await repository.findLiveStreamById(
              favorite.streamId,
            );

            if (liveStream != null) {
              return ContentItem(
                liveStream.streamId,
                liveStream.name,
                liveStream.streamIcon,
                ContentType.liveStream,
                liveStream: liveStream,
              );
            }
            break;

          case ContentType.vod:
            final movie = await _database.findMovieById(
              favorite.streamId,
              AppState.currentPlaylist!.id,
            );

            if (movie != null) {
              return ContentItem(
                favorite.streamId,
                favorite.name,
                favorite.imagePath ?? '',
                ContentType.vod,
                containerExtension: movie.containerExtension,
                vodStream: movie,
              );
            }
            break;
          case ContentType.series:
            final series = await repository.getSeries(categoryId: '');
            final seriesStream = series?.firstWhere(
              (serie) => serie.seriesId == favorite.streamId,
            );
            if (seriesStream != null) {
              return ContentItem(
                seriesStream.seriesId,
                seriesStream.name,
                seriesStream.cover ?? '',
                ContentType.series,
                seriesStream: seriesStream,
              );
            }
            break;
        }
      } else if (isM3u) {
        final repository = M3uRepository();

        switch (favorite.contentType) {
          case ContentType.liveStream:
            final m3uItem = await repository.getM3uItemById(
              id: favorite.m3uItemId ?? '',
            );
            if (m3uItem != null) {
              return ContentItem(
                m3uItem.url,
                m3uItem.name ?? 'NO NAME',
                m3uItem.tvgLogo ?? '',
                ContentType.liveStream,
                m3uItem: m3uItem,
              );
            }
            break;

          case ContentType.vod:
            final m3uItems = await repository.getM3uItemsByCategoryId(
              categoryId: '',
              contentType: ContentType.vod,
            );
            final m3uItem = m3uItems?.firstWhere(
              (item) => item.url == favorite.streamId,
            );
            if (m3uItem != null) {
              return ContentItem(
                m3uItem.url,
                m3uItem.name ?? 'NO NAME',
                m3uItem.tvgLogo ?? '',
                ContentType.vod,
                m3uItem: m3uItem,
              );
            }
            break;

          case ContentType.series:
            final series = await repository.getSeriesByCategoryId(
              categoryId: '',
            );
            final m3uSerie = series?.firstWhere(
              (serie) => serie.seriesId == favorite.streamId,
            );
            if (m3uSerie != null) {
              return ContentItem(
                m3uSerie.seriesId,
                m3uSerie.name,
                m3uSerie.cover ?? '',
                ContentType.series,
              );
            }
            break;
        }
      }

      // Eğer gerçek veri bulunamazsa, basit ContentItem döndür
      return ContentItem(
        favorite.streamId,
        favorite.name,
        favorite.imagePath ?? '',
        favorite.contentType,
      );
    } catch (e) {
      // Hata durumunda basit ContentItem döndür
      return ContentItem(
        favorite.streamId,
        favorite.name,
        favorite.imagePath ?? '',
        favorite.contentType,
      );
    }
  }
}
