import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:http/http.dart' as http;
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/api_configuration_model.dart';
import 'package:another_iptv_player/models/api_response.dart';
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/live_stream.dart';
import 'package:another_iptv_player/models/series_response.dart';
import 'package:another_iptv_player/models/vod_streams.dart';
import 'package:another_iptv_player/models/series.dart';
import 'package:another_iptv_player/utils/type_convertions.dart';
import '../models/category_type.dart';
import '../services/service_locator.dart';

class IptvRepository {
  final ApiConfig _config;
  final String _playlistId;
  final _database = getIt<AppDatabase>();

  IptvRepository(this._config, this._playlistId);

  Future<http.Response> _makeRequest(
    String endpoint, {
    Map<String, String>? additionalParams,
  }) async {
    final params = Map<String, String>.from(_config.baseParams);
    if (additionalParams != null) {
      params.addAll(additionalParams);
    }

    final uri = Uri.parse(
      '${_config.baseUrl}/$endpoint',
    ).replace(queryParameters: params);

    return await http.get(uri, headers: {'Content-Type': 'application/json'});
  }

  Future<ApiResponse?> getPlayerInfo({bool forceRefresh = false}) async {
    try {
      if (!forceRefresh) {
        var userInfo = await _database.getUserInfoByPlaylistId(_playlistId);
        var serverInfo = await _database.getServerInfoByPlaylistId(_playlistId);

        if (userInfo != null && serverInfo != null) {
          return ApiResponse(
            userInfo: userInfo,
            serverInfo: serverInfo,
            playlistId: _playlistId,
          );
        }
      }

      final response = await _makeRequest('player_api.php');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        var apiResponse = ApiResponse.fromJson(jsonData, _playlistId);

        await _database.insertOrUpdateUserInfo(apiResponse.userInfo);
        await _database.insertOrUpdateServerInfo(apiResponse.serverInfo);

        return apiResponse;
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      print('Player Info Error: $e');
      return null;
    }
  }

  Future<List<LiveStream>?> getLiveChannels({
    String? categoryId,
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh) {
        var liveStreams = await _database.getLiveStreams(_playlistId);

        if (liveStreams.isNotEmpty) {
          return liveStreams;
        }
      }

      final additionalParams = <String, String>{'action': 'get_live_streams'};

      if (categoryId != null) {
        additionalParams['category_id'] = categoryId;
      }

      final response = await _makeRequest(
        'player_api.php',
        additionalParams: additionalParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        var liveStreams = jsonData
            .map((json) => LiveStream.fromJson(json, _playlistId))
            .toList();

        await _database.deleteLiveStreamsByPlaylistId(_playlistId);
        await _database.insertLiveStreams(liveStreams);
        return liveStreams;
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      print('Live Channels Error: $e');
      return null;
    }
  }

  Future<List<LiveStream>?> getLiveChannelsByCategoryId({
    required String categoryId,
    bool forceRefresh = false,
    int? top,
  }) async {
    try {
      if (!forceRefresh) {
        var liveStreams = await _database.getLiveStreamsByCategoryId(
          _playlistId,
          categoryId,
          top: top,
        );

        if (liveStreams.isNotEmpty) {
          return liveStreams;
        }
      }

      final additionalParams = <String, String>{'action': 'get_live_streams'};

      additionalParams['category_id'] = categoryId;

      final response = await _makeRequest(
        'player_api.php',
        additionalParams: additionalParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        var liveStreams = jsonData
            .map((json) => LiveStream.fromJson(json, _playlistId))
            .toList();

        await _database.deleteLiveStreamsByPlaylistId(_playlistId);
        await _database.insertLiveStreams(liveStreams);
        return liveStreams;
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      print('Live Channels Error: $e');
      return null;
    }
  }

  Future<List<VodStream>?> getMovies({
    String? categoryId,
    bool forceRefresh = false,
    int? top,
  }) async {
    try {
      if (!forceRefresh) {
        if (categoryId != null) {
          var vodStreams = await _database.getVodStreamsByCategoryAndPlaylistId(
            categoryId: categoryId,
            playlistId: _playlistId,
            top: top,
          );

          if (vodStreams.isNotEmpty) {
            return vodStreams;
          }
        } else {
          var vodStreams = await _database.getVodStreamsByPlaylistId(
            _playlistId,
          );

          if (vodStreams.isNotEmpty) {
            return vodStreams;
          }
        }
      }

      final additionalParams = <String, String>{'action': 'get_vod_streams'};

      if (categoryId != null) {
        additionalParams['category_id'] = categoryId;
      }

      final response = await _makeRequest(
        'player_api.php',
        additionalParams: additionalParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        var vodStreams = jsonData
            .map((json) => VodStream.fromJson(json, _playlistId))
            .toList();

        await _database.deleteVodStreamsByPlaylistId(_playlistId);
        await _database.insertVodStreams(vodStreams);

        return vodStreams;
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      print('Movies Error: $e');
      return null;
    }
  }

  Future<List<SeriesStream>?> getSeries({
    String? categoryId,
    bool forceRefresh = false,
    int? top,
  }) async {
    try {
      if (!forceRefresh) {
        if (categoryId != null) {
          var series = await _database.getSeriesStreamsByCategoryAndPlaylistId(
            categoryId: categoryId,
            playlistId: _playlistId,
            top: top,
          );

          if (series.isNotEmpty) {
            return series;
          }
        } else {
          var series = await _database.getSeriesStreamsByPlaylistId(
            _playlistId,
          );

          if (series.isNotEmpty) {
            return series;
          }
        }
      }

      final additionalParams = <String, String>{'action': 'get_series'};

      if (categoryId != null) {
        additionalParams['category_id'] = categoryId;
      }

      final response = await _makeRequest(
        'player_api.php',
        additionalParams: additionalParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        var series = jsonData
            .map((json) => SeriesStream.fromJson(json, _playlistId))
            .toList();

        await _database.deleteSeriesStreamsByPlaylistId(_playlistId);
        await _database.insertSeriesStreams(series);

        return series;
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      print('Series Error: $e');
      return null;
    }
  }

  Future<List<Category>?> getLiveCategories({bool forceRefresh = false}) async {
    return _getCategories(
      CategoryType.live,
      'get_live_categories',
      forceRefresh,
    );
  }

  Future<List<Category>?> getVodCategories({bool forceRefresh = false}) async {
    return _getCategories(CategoryType.vod, 'get_vod_categories', forceRefresh);
  }

  Future<List<Category>?> getSeriesCategories({
    bool forceRefresh = false,
  }) async {
    return _getCategories(
      CategoryType.series,
      'get_series_categories',
      forceRefresh,
    );
  }

  Future<List<Category>?> _getCategories(
    CategoryType type,
    String action,
    bool forceRefresh,
  ) async {
    try {
      if (!forceRefresh) {
        final cachedCategories = await _database.getCategoriesByTypeAndPlaylist(
          _playlistId,
          type,
        );
        if (cachedCategories.isNotEmpty) {
          return cachedCategories;
        }
      }

      final additionalParams = <String, String>{'action': action};

      final response = await _makeRequest(
        'player_api.php',
        additionalParams: additionalParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        final categories = jsonData
            .map((json) => Category.fromJson(json, _playlistId, type))
            .toList();

        await _database.deleteCategoriesByTypeAndPlaylist(_playlistId, type);
        await _database.insertCategories(categories);

        return categories;
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      print('${type.value} Categories Error: $e');
      // Hata durumunda cache'den dön
      final cachedCategories = await _database.getCategoriesByTypeAndPlaylist(
        _playlistId,
        type,
      );
      return cachedCategories.isNotEmpty ? cachedCategories : null;
    }
  }

  Future<Map<CategoryType, List<Category>>?> getAllCategories({
    bool forceRefresh = false,
  }) async {
    try {
      final results = await Future.wait([
        getLiveCategories(forceRefresh: forceRefresh),
        getVodCategories(forceRefresh: forceRefresh),
        getSeriesCategories(forceRefresh: forceRefresh),
      ]);

      return {
        CategoryType.live: results[0] ?? [],
        CategoryType.vod: results[1] ?? [],
        CategoryType.series: results[2] ?? [],
      };
    } catch (e) {
      print('Get All Categories Error: $e');
      return await _database.getAllCategoriesByPlaylist(_playlistId);
    }
  }

  Future<void> clearCategoriesCache({CategoryType? type}) async {
    if (type != null) {
      await _database.deleteCategoriesByTypeAndPlaylist(_playlistId, type);
    } else {
      await _database.deleteAllCategoriesByPlaylist(_playlistId);
    }
  }

  Future<List<Category>> searchCategories(
    CategoryType type,
    String query,
  ) async {
    return await _database.searchCategories(_playlistId, type, query);
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

  Future<SeriesDetailResponse?> getSeriesInfo(
    String seriesId, {
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh) {
        final seriesInfo = await _database.getSeriesInfo(seriesId, _playlistId);
        final seasons = await _database.getSeasonsBySeriesId(
          seriesId,
          _playlistId,
        );
        final episodes = await _database.getEpisodesBySeriesId(
          seriesId,
          _playlistId,
        );

        if (seriesInfo != null && seasons.isNotEmpty) {
          return SeriesDetailResponse(
            seriesInfo: seriesInfo,
            seasons: seasons,
            episodes: episodes,
            playlistId: _playlistId,
          );
        }
      }

      final response = await _makeRequest(
        'player_api.php',
        additionalParams: {'action': 'get_series_info', 'series_id': seriesId},
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);

        await _saveSeriesDataToDatabase(seriesId, jsonData);

        final seriesInfo = await _database.getSeriesInfo(seriesId, _playlistId);
        final seasons = await _database.getSeasonsBySeriesId(
          seriesId,
          _playlistId,
        );
        final episodes = await _database.getEpisodesBySeriesId(
          seriesId,
          _playlistId,
        );

        return SeriesDetailResponse(
          seriesInfo: seriesInfo!,
          seasons: seasons,
          episodes: episodes,
          playlistId: _playlistId,
        );
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      print('Series Info Error: $e');
      return null;
    }
  }

  Future<List<EpisodesData>> getSeriesEpisodesBySeason(
    String seriesId,
    int seasonNumber, {
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh) {
        final episodes = await _database.getEpisodesBySeason(
          seriesId,
          seasonNumber,
          _playlistId,
        );
        if (episodes.isNotEmpty) {
          return episodes;
        }
      }

      // Eğer episodlar yok ise series info'yu çek
      await getSeriesInfo(seriesId, forceRefresh: true);

      return await _database.getEpisodesBySeason(
        seriesId,
        seasonNumber,
        _playlistId,
      );
    } catch (e) {
      print('Get Episodes By Season Error: $e');
      return [];
    }
  }

  Future<void> _saveSeriesDataToDatabase(
    String seriesId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _database.clearSeriesData(seriesId, _playlistId);

      final info = data['info'];
      if (info != null) {
        final seriesInfoCompanion = SeriesInfosCompanion(
          seriesId: drift.Value(seriesId),
          playlistId: drift.Value(_playlistId),
          name: drift.Value(safeString(info['name'])),
          cover: drift.Value(safeString(info['cover'])),
          plot: drift.Value(safeString(info['plot'])),
          cast: drift.Value(safeString(info['cast'])),
          director: drift.Value(safeString(info['director'])),
          genre: drift.Value(safeString(info['genre'])),
          releaseDate: drift.Value(safeString(info['releaseDate'])),
          lastModified: drift.Value(safeString(info['last_modified'])),
          rating: drift.Value(safeString(info['rating'])),
          rating5based: drift.Value(safeInt(info['rating_5based'])),
          backdropPath: drift.Value(
            getFirstBackdropPath(info['backdrop_path']),
          ),
          youtubeTrailer: drift.Value(safeString(info['youtube_trailer'])),
          episodeRunTime: drift.Value(safeString(info['episode_run_time'])),
          categoryId: drift.Value(safeString(info['category_id'])),
        );

        await _database.insertSeriesInfo(seriesInfoCompanion);
      }

      final seasons = data['seasons'];
      if (seasons is List) {
        for (final season in seasons) {
          final seasonCompanion = SeasonsCompanion(
            seriesId: drift.Value(seriesId),
            playlistId: drift.Value(_playlistId),
            airDate: drift.Value(safeString(season['air_date'])),
            episodeCount: drift.Value(safeInt(season['episode_count'])),
            seasonId: drift.Value(safeInt(season['id']) ?? 0),
            name: drift.Value(safeString(season['name'])),
            overview: drift.Value(safeString(season['overview'])),
            seasonNumber: drift.Value(safeInt(season['season_number']) ?? 1),
            voteAverage: drift.Value(safeInt(season['vote_average'])),
            cover: drift.Value(safeString(season['cover'])),
            coverBig: drift.Value(safeString(season['cover_big'])),
          );

          await _database.insertSeason(seasonCompanion);
        }
      }

      final episodes = data['episodes'];
      if (episodes is Map<String, dynamic>) {
        for (final seasonKey in episodes.keys) {
          final seasonEpisodes = episodes[seasonKey];

          if (seasonEpisodes is List) {
            for (final episode in seasonEpisodes) {
              dynamic info = episode['info'];

              final episodeCompanion = EpisodesCompanion(
                seriesId: drift.Value(seriesId),
                playlistId: drift.Value(_playlistId),
                episodeId: drift.Value(safeString(episode['id'])),
                episodeNum: drift.Value(safeInt(episode['episode_num']) ?? 0),
                title: drift.Value(safeString(episode['title'])),
                containerExtension: drift.Value(
                  safeString(episode['container_extension']),
                ),
                season: drift.Value(safeInt(episode['season']) ?? 1),
                customSid: drift.Value(safeString(episode['custom_sid'])),
                added: drift.Value(safeString(episode['added'])),
                directSource: drift.Value(safeString(episode['direct_source'])),

                tmdbId: drift.Value(
                  safeInt(info is Map ? info['tmdb_id'] : null),
                ),
                releasedate: drift.Value(
                  safeString(info is Map ? info['releasedate'] : null),
                ),
                plot: drift.Value(
                  safeString(info is Map ? info['plot'] : null),
                ),
                durationSecs: drift.Value(
                  safeInt(info is Map ? info['duration_secs'] : null),
                ),
                duration: drift.Value(
                  safeString(info is Map ? info['duration'] : null),
                ),
                movieImage: drift.Value(
                  safeString(info is Map ? info['movie_image'] : null),
                ),
                bitrate: drift.Value(
                  safeInt(info is Map ? info['bitrate'] : null),
                ),
                rating: drift.Value(
                  safeDouble(info is Map ? info['rating'] : null),
                ),
              );

              print('TMDB ->${info is Map ? info['tmdb_id'] : null}');

              await _database.insertEpisode(episodeCompanion);
            }
          }
        }
      }

      print('Series data saved to database successfully');
    } catch (e) {
      print('Save series data to database error: $e');
      rethrow;
    }
  }
}
