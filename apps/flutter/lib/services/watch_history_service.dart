import 'package:drift/drift.dart';
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/watch_history.dart';
import 'package:another_iptv_player/services/service_locator.dart';

class WatchHistoryService {
  final _database = getIt<AppDatabase>();

  WatchHistoryService();

  Future<void> saveWatchHistory(WatchHistory history) async {
    await _database
        .into(_database.watchHistories)
        .insertOnConflictUpdate(history.toDriftCompanion());
  }

  Future<WatchHistory?> getWatchHistory(
    String playlistId,
    String streamId,
  ) async {
    final query = _database.select(_database.watchHistories)
      ..where(
        (tbl) =>
            tbl.playlistId.equals(playlistId) & tbl.streamId.equals(streamId),
      );

    final result = await query.getSingleOrNull();
    return result != null ? WatchHistory.fromDrift(result) : null;
  }

  Future<List<WatchHistory>> getWatchHistoryByPlaylist(
    String playlistId,
  ) async {
    final query = _database.select(_database.watchHistories)
      ..where((tbl) => tbl.playlistId.equals(playlistId))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastWatched)]);

    final results = await query.get();
    return results.map((data) => WatchHistory.fromDrift(data)).toList();
  }

  Future<List<WatchHistory>> getWatchHistoryByContentType(
    ContentType contentType, String playlistId
  ) async {
    final query = _database.select(_database.watchHistories)
      ..where((tbl) => tbl.contentType.equals(contentType.index) & tbl.playlistId.equals(playlistId))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastWatched)]);

    final results = await query.get();
    return results.map((data) => WatchHistory.fromDrift(data)).toList();
  }

  Future<List<WatchHistory>> getRecentlyWatched(
    String playlistId, {
    int limit = 10,
  }) async {
    final query = _database.select(_database.watchHistories)
      ..where((tbl) => tbl.playlistId.equals(playlistId))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastWatched)])
      ..limit(limit);

    final results = await query.get();
    return results.map((data) => WatchHistory.fromDrift(data)).toList();
  }

  Future<List<WatchHistory>> getContinueWatching(String playlistId) async {
    final query = _database.select(_database.watchHistories)
      ..where(
        (tbl) =>
            tbl.watchDuration.isNotNull() &
            tbl.totalDuration.isNotNull() &
            tbl.playlistId.equals(playlistId),
      )
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastWatched)]);

    final results = await query.get();
    return results.map((data) => WatchHistory.fromDrift(data)).toList();
  }

  Future<void> deleteWatchHistory(String playlistId, String streamId) async {
    await (_database.delete(_database.watchHistories)..where(
          (tbl) =>
              tbl.playlistId.equals(playlistId) & tbl.streamId.equals(streamId),
        ))
        .go();
  }

  Future<void> deletePlaylistHistory(String playlistId) async {
    await (_database.delete(
      _database.watchHistories,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  Future<void> clearAllHistory() async {
    await _database.delete(_database.watchHistories).go();
  }
}
