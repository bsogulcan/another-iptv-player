import 'package:another_iptv_player/database/database.dart';

class SeriesDetailResponse {
  final SeriesInfosData seriesInfo;
  final List<SeasonsData> seasons;
  final List<EpisodesData> episodes;
  final String playlistId;

  SeriesDetailResponse({
    required this.seriesInfo,
    required this.seasons,
    required this.episodes,
    required this.playlistId,
  });
}