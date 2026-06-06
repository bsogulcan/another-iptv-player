import 'package:drift/drift.dart';

import '../database/database.dart';

class M3uSerie {
  final String playlistId;
  final String seriesId;
  final String name;
  final String? categoryId;
  final String? cover;

  M3uSerie({
    required this.playlistId,
    required this.seriesId,
    required this.name,
    this.categoryId,
    this.cover,
  });

  M3uSeriesCompanion toCompanion() {
    return M3uSeriesCompanion(
      playlistId: Value(playlistId),
      seriesId: Value(seriesId),
      name: Value(name),
      categoryId: Value(categoryId),
      cover: Value(cover),
    );
  }

  factory M3uSerie.fromData(M3uSeriesData data) {
    return M3uSerie(
      playlistId: data.playlistId,
      seriesId: data.seriesId,
      name: data.name,
      categoryId: data.categoryId,
      cover: data.cover,
    );
  }
}

class M3uEpisode {
  final String playlistId;
  final String seriesId;
  final int seasonNumber;
  final int episodeNumber;
  final String name;
  final String url;
  final String? categoryId;
  final String? cover;

  M3uEpisode({
    required this.playlistId,
    required this.seriesId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.name,
    required this.url,
    this.categoryId,
    this.cover,
  });

  M3uEpisodesCompanion toCompanion() {
    return M3uEpisodesCompanion(
      playlistId: Value(playlistId),
      seriesId: Value(seriesId),
      seasonNumber: Value(seasonNumber),
      episodeNumber: Value(episodeNumber),
      name: Value(name),
      url: Value(url),
      categoryId: Value(categoryId),
      cover: Value(cover),
    );
  }

  factory M3uEpisode.fromData(M3uEpisodesData data) {
    return M3uEpisode(
      playlistId: data.playlistId,
      seriesId: data.seriesId,
      seasonNumber: data.seasonNumber,
      episodeNumber: data.episodeNumber,
      name: data.name,
      url: data.url,
      categoryId: data.categoryId,
      cover: data.cover,
    );
  }
}
