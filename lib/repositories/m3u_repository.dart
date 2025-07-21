import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/live_stream.dart';
import 'package:another_iptv_player/models/m3u_series.dart';
import 'package:another_iptv_player/services/app_state.dart';

import '../models/m3u_item.dart';
import '../models/series.dart';
import '../models/vod_streams.dart';
import '../services/service_locator.dart';

class M3uRepository {
  final String _playlistId = AppState.currentPlaylist!.id;
  final _database = getIt<AppDatabase>();

  M3uRepository();

  Future<List<Category>?> getCategories() async {
    return await _database.getCategoriesByPlaylist(_playlistId);
  }

  Future<List<M3uItem>?> getM3uItemsByCategoryId({
    required String categoryId,
    int? top,
    ContentType? contentType,
  }) async {
    var liveStreams = await _database.getM3uItemsByCategoryId(
      _playlistId,
      categoryId,
      top: top,
      contentType: contentType,
    );

    if (liveStreams.isNotEmpty) {
      return liveStreams;
    }
    return null;
  }

  Future<List<M3uItem>?> getM3uItems({
    int? top,
    ContentType? contentType,
  }) async {
    var liveStreams = await _database.getM3uItemsByPlaylist(
      _playlistId,
    );

    if (liveStreams.isNotEmpty) {
      return liveStreams;
    }
    return null;
  }


  Future<List<LiveStream>> searchLiveStreams(String query) async {
    return await _database.searchLiveStreams(_playlistId, query);
  }

  Future<List<VodStream>> searchMovies(String query) async {
    return await _database.searchMovie(_playlistId, query);
  }

  Future<List<SeriesStream>> searchSeries(String query) async {
    return await _database.searchSeries(_playlistId, query);
  }

  Future<List<M3uSerie>?> getSeriesByCategoryId({
    required String categoryId,
    int? top
  }) async {
    var liveStreams = await _database.getM3uSeriesByCategoryId(
      _playlistId,
      categoryId,
      top: top,
    );

    if (liveStreams.isNotEmpty) {
      return liveStreams;
    }
    return null;
  }

  Future<List<M3uEpisode>?> getM3uEpisodesBySeriesId({required String seriesId}) async {
    var episodes = await _database.getM3uEpisodesBySeriesId(
      _playlistId,
      seriesId
    );

    if (episodes.isNotEmpty) {
      return episodes;
    }
    return null;
  }
}
