import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/utils/type_convertions.dart';

class SeriesStream {
  final String playlistId;
  final String seriesId;
  final String name;
  final String? cover;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final String? lastModified;
  final String? rating;
  final double? rating5based;
  final List<String>? backdropPath;
  final String? youtubeTrailer;
  final String? episodeRunTime;
  final String? categoryId;

  SeriesStream({
    required this.playlistId,
    required this.seriesId,
    required this.name,
    this.cover,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.lastModified,
    this.rating,
    this.rating5based,
    this.backdropPath,
    this.youtubeTrailer,
    this.episodeRunTime,
    this.categoryId,
  });

  factory SeriesStream.fromJson(Map<String, dynamic> json, String playlistId) {
    List<String> backdropPaths = [];
    final rawBackdrop = json['backdrop_path'];
    if (rawBackdrop is List) {
      backdropPaths = rawBackdrop.map((item) => safeString(item)).toList();
    } else if (rawBackdrop is String) {
      final safeBackdrop = safeString(rawBackdrop);
      if (safeBackdrop.isNotEmpty) {
        backdropPaths = [safeBackdrop];
      }
    }

    return SeriesStream(
      seriesId: safeString(json['series_id']),
      name: safeString(json['name']),
      cover: safeString(json['cover']),
      plot: safeString(json['plot']),
      cast: safeString(json['cast']),
      director: safeString(json['director']),
      genre: safeString(json['genre']),
      releaseDate: safeString(json['releaseDate']),
      lastModified: safeString(json['last_modified']),
      rating: safeString(json['rating']),
      rating5based: safeDouble(json['rating_5based']) ?? 0.0,
      backdropPath: backdropPaths,
      youtubeTrailer: safeString(json['youtube_trailer']),
      episodeRunTime: safeString(json['episode_run_time']),
      categoryId: safeString(json['category_id']),
      playlistId: safeString(playlistId),
    );
  }

  factory SeriesStream.fromDriftSeriesStream(
    SeriesStreamsData driftSeriesStream,
  ) {
    List<String> backdropPaths = [];
    if (driftSeriesStream.backdropPath != null &&
        driftSeriesStream.backdropPath!.isNotEmpty) {
      try {
        final decoded = jsonDecode(driftSeriesStream.backdropPath!);
        if (decoded is List) {
          backdropPaths = decoded.map((item) => item.toString()).toList();
        }
      } catch (e) {
        backdropPaths = driftSeriesStream.backdropPath!
            .split(',')
            .where((item) => item.trim().isNotEmpty)
            .toList();
      }
    }

    return SeriesStream(
      seriesId: driftSeriesStream.seriesId,
      name: driftSeriesStream.name,
      cover: driftSeriesStream.cover,
      plot: driftSeriesStream.plot,
      cast: driftSeriesStream.cast,
      director: driftSeriesStream.director,
      genre: driftSeriesStream.genre,
      releaseDate: driftSeriesStream.releaseDate,
      lastModified: driftSeriesStream.lastModified,
      rating: driftSeriesStream.rating,
      rating5based: driftSeriesStream.rating5based,
      backdropPath: backdropPaths,
      youtubeTrailer: driftSeriesStream.youtubeTrailer,
      episodeRunTime: driftSeriesStream.episodeRunTime,
      categoryId: driftSeriesStream.categoryId,
      playlistId: driftSeriesStream.playlistId,
    );
  }

  SeriesStreamsCompanion toDriftCompanion() {
    String backdropPathJson = '';
    if (backdropPath != null && backdropPath!.isNotEmpty) {
      backdropPathJson = jsonEncode(backdropPath);
    }

    return SeriesStreamsCompanion(
      seriesId: Value(seriesId),
      name: Value(name),
      cover: Value(cover),
      plot: Value(plot),
      cast: Value(cast),
      director: Value(director),
      genre: Value(genre),
      releaseDate: Value(releaseDate),
      lastModified: Value(lastModified),
      rating: Value(rating),
      rating5based: Value(rating5based),
      backdropPath: Value(backdropPathJson),
      youtubeTrailer: Value(youtubeTrailer),
      episodeRunTime: Value(episodeRunTime),
      categoryId: Value(categoryId),
      playlistId: Value(playlistId),
    );
  }

  @override
  String toString() {
    return 'SeriesStream{seriesId: $seriesId, name: $name, categoryId: $categoryId, rating: $rating, playlistId: $playlistId, lastModified: $lastModified, backdropPath: $backdropPath}';
  }
}
