import 'package:drift/drift.dart';
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/utils/type_convertions.dart';

class LiveStream {
  final String streamId;
  final String name;
  final String streamIcon;
  final String categoryId;
  final String epgChannelId;
  final String? playlistId;

  LiveStream({
    required this.streamId,
    required this.name,
    required this.streamIcon,
    required this.categoryId,
    required this.epgChannelId,
    this.playlistId,
  });

  factory LiveStream.fromJson(Map<String, dynamic> json, String playlistId) {
    return LiveStream(
      streamId: safeString(json['stream_id']),
      name: safeString(json['name']),
      streamIcon: safeString(json['stream_icon']),
      categoryId: safeString(json['category_id']),
      epgChannelId: safeString(json['epg_channel_id']),
      playlistId: safeString(playlistId),
    );
  }

  factory LiveStream.fromDriftLiveStream(LiveStreamsData driftLiveStream) {
    return LiveStream(
      streamId: driftLiveStream.streamId,
      name: driftLiveStream.name,
      streamIcon: driftLiveStream.streamIcon,
      categoryId: driftLiveStream.categoryId,
      epgChannelId: driftLiveStream.epgChannelId,
      playlistId: driftLiveStream.playlistId,
    );
  }

  LiveStreamsCompanion toDriftCompanion(String playlistId) {
    return LiveStreamsCompanion(
      streamId: Value(streamId),
      name: Value(name),
      streamIcon: Value(streamIcon),
      categoryId: Value(categoryId),
      epgChannelId: Value(epgChannelId),
      playlistId: Value(playlistId),
    );
  }
}
