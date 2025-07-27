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

  Future<void> addFavorite(ContentItem contentItem) async {
    final playlistId = AppState.currentPlaylist!.id;

    final isAlreadyFavorite = await _database.isFavorite(
      playlistId,
      contentItem.id,
      contentItem.contentType,
      contentItem.season != null ? contentItem.id : null,
    );

    if (isAlreadyFavorite) {
      throw Exception('Bu içerik zaten favorilerde');
    }

    final favorite = Favorite(
      id: _uuid.v4(),
      playlistId: playlistId,
      contentType: contentItem.contentType,
      streamId: contentItem.id,
      m3uItemId: contentItem.m3uItem?.id,
      name: contentItem.name,
      imagePath: contentItem.imagePath,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _database.insertFavorite(favorite);
  }

  Future<void> removeFavorite(
    String streamId,
    ContentType contentType, {
    String? episodeId,
  }) async {
    final playlistId = AppState.currentPlaylist!.id;

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

  Future<List<Favorite>> getAllFavorites() async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.getFavoritesByPlaylist(playlistId);
  }

  Future<List<Favorite>> getFavoritesByContentType(
    ContentType contentType,
  ) async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.getFavoritesByContentType(playlistId, contentType);
  }

  Future<List<Favorite>> getLiveStreamFavorites() async {
    return await getFavoritesByContentType(ContentType.liveStream);
  }

  Future<List<Favorite>> getMovieFavorites() async {
    return await getFavoritesByContentType(ContentType.vod);
  }

  Future<List<Favorite>> getSeriesFavorites() async {
    return await getFavoritesByContentType(ContentType.series);
  }

  Future<int> getFavoriteCount() async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.getFavoriteCount(playlistId);
  }

  Future<int> getFavoriteCountByContentType(ContentType contentType) async {
    final playlistId = AppState.currentPlaylist!.id;
    return await _database.getFavoriteCountByContentType(
      playlistId,
      contentType,
    );
  }

  Future<bool> toggleFavorite(ContentItem contentItem) async {
    final playlistId = AppState.currentPlaylist!.id;
    final isCurrentlyFavorite = await _database.isFavorite(
      playlistId,
      contentItem.id,
      contentItem.contentType,
      null
    );

    if (isCurrentlyFavorite) {
      await removeFavorite(
        contentItem.id,
        contentItem.contentType
      );
      return false;
    } else {
      await addFavorite(contentItem);
      return true;
    }
  }

  Future<void> updateFavorite(Favorite favorite) async {
    await _database.updateFavorite(favorite);
  }

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
            final m3uItem = await repository.getM3uItemById(
              id: favorite.m3uItemId ?? '',
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
            final m3uItem = await repository.getM3uItemById(
              id: favorite.m3uItemId ?? '',
            );

            if (m3uItem != null) {
              return ContentItem(
                m3uItem.id,
                m3uItem.name ?? '',
                m3uItem.tvgLogo ?? '',
                ContentType.series,
                m3uItem: m3uItem,
              );
            }
            break;
        }
      }

      return ContentItem(
        favorite.streamId,
        favorite.name,
        favorite.imagePath ?? '',
        favorite.contentType,
      );
    } catch (e) {
      return ContentItem(
        favorite.streamId,
        favorite.name,
        favorite.imagePath ?? '',
        favorite.contentType,
      );
    }
  }
}
