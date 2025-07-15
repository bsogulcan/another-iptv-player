import 'package:flutter/material.dart';
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/watch_history.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/watch_history_service.dart';
import 'package:another_iptv_player/utils/navigate_by_content_type.dart';
import '../services/service_locator.dart';
import '../screens/series/episode_screen.dart';

class WatchHistoryController extends ChangeNotifier {
  late WatchHistoryService _historyService;
  late IptvRepository _repository;
  final _database = getIt<AppDatabase>();

  List<WatchHistory> _continueWatching = [];
  List<WatchHistory> _recentlyWatched = [];
  List<WatchHistory> _liveHistory = [];
  List<WatchHistory> _movieHistory = [];
  List<WatchHistory> _seriesHistory = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Getters
  List<WatchHistory> get continueWatching => _continueWatching;
  List<WatchHistory> get recentlyWatched => _recentlyWatched;
  List<WatchHistory> get liveHistory => _liveHistory;
  List<WatchHistory> get movieHistory => _movieHistory;
  List<WatchHistory> get seriesHistory => _seriesHistory;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  WatchHistoryController() {
    _historyService = WatchHistoryService();
    _repository = AppState.xtreamCodeRepository!;
  }

  bool get isAllEmpty =>
      _continueWatching.isEmpty &&
          _recentlyWatched.isEmpty &&
          _liveHistory.isEmpty &&
          _movieHistory.isEmpty &&
          _seriesHistory.isEmpty;

  Future<void> loadWatchHistory() async {
    _setLoading(true);
    _clearError();

    final playlistId = AppState.currentPlaylist!.id;

    try {
      final futures = await Future.wait([
        _historyService.getContinueWatching(playlistId),
        _historyService.getRecentlyWatched(limit: 20, playlistId),
        _historyService.getWatchHistoryByContentType(ContentType.liveStream, playlistId),
        _historyService.getWatchHistoryByContentType(ContentType.vod, playlistId),
        _historyService.getWatchHistoryByContentType(ContentType.series, playlistId),
      ]);

      _continueWatching = futures[0];
      _recentlyWatched = futures[1];
      _liveHistory = futures[2];
      _movieHistory = futures[3];
      _seriesHistory = futures[4];

      _setLoading(false);
    } catch (e) {
      _setError('İzleme geçmişi yüklenirken hata oluştu: $e');
      _setLoading(false);
    }
  }

  Future<void> playContent(BuildContext context, WatchHistory history) async {
    try {
      switch (history.contentType) {
        case ContentType.liveStream:
          await _playLiveStream(context, history);
          break;
        case ContentType.vod:
          await _playMovie(context, history);
          break;
        case ContentType.series:
          await _playSeries(context, history);
          break;
      }
    } catch (e) {
      _setError('Video oynatılırken hata oluştu: $e');
    }
  }

  Future<void> removeHistory(WatchHistory history) async {
    try {
      await _historyService.deleteWatchHistory(history.playlistId, history.streamId);
      await loadWatchHistory();
    } catch (e) {
      _setError('Hata oluştu: $e');
    }
  }

  Future<void> clearAllHistory() async {
    try {
      await _historyService.clearAllHistory();
      await loadWatchHistory();
    } catch (e) {
      _setError('Hata oluştu: $e');
    }
  }

  // Private methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _playLiveStream(BuildContext context, WatchHistory history) async {
    final liveStream = await _database.findLiveStreamById(
      history.streamId,
      AppState.currentPlaylist!.id,
    );

    navigateByContentType(
      context,
      ContentItem(
        history.streamId,
        history.title,
        history.imagePath ?? '',
        history.contentType,
        liveStream: liveStream,
      ),
    );
  }

  Future<void> _playMovie(BuildContext context, WatchHistory history) async {
    final movie = await _database.findMovieById(
      history.streamId,
      AppState.currentPlaylist!.id,
    );

    navigateByContentType(
      context,
      ContentItem(
        history.streamId,
        history.title,
        history.imagePath ?? '',
        history.contentType,
        containerExtension: movie!.containerExtension,
        vodStream: movie,
      ),
    );
  }

  Future<void> _playSeries(BuildContext context, WatchHistory history) async {
    final episode = await _database.findEpisodesById(
      history.streamId,
      AppState.currentPlaylist!.id,
    );

    final seriesResponse = await _repository.getSeriesInfo(episode!.seriesId);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EpisodeScreen(
          seriesInfo: seriesResponse!.seriesInfo,
          seasons: seriesResponse.seasons,
          episodes: seriesResponse.episodes,
          contentItem: ContentItem(
            episode.episodeId.toString(),
            history.title,
            history.imagePath ?? "",
            ContentType.series,
            containerExtension: episode.containerExtension,
            season: episode.season,
          ),
          watchHistory: history,
        ),
      ),
    );
  }
}