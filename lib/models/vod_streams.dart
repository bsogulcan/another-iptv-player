import 'package:drift/drift.dart';
import 'package:iptv_player/database/database.dart';
import 'package:iptv_player/utils/type_convertions.dart';

class VodStream {
  final String streamId;
  final String name;
  final String streamIcon;
  final String categoryId;
  final String rating;
  final double rating5based;
  final String containerExtension;
  final String? playlistId;

  VodStream({
    required this.streamId,
    required this.name,
    required this.streamIcon,
    required this.categoryId,
    required this.rating,
    required this.rating5based,
    required this.containerExtension,
    this.playlistId,
  });

  factory VodStream.fromJson(Map<String, dynamic> json, String playlistId) {
    return VodStream(
      streamId: safeString(json['stream_id']),
      name: safeString(json['name']),
      streamIcon: safeString(json['stream_icon']),
      categoryId: safeString(json['category_id']),
      rating: safeString(json['rating']),
      rating5based: safeDouble(json['rating_5based']) ?? 0.0,
      containerExtension: safeString(json['container_extension']),
      playlistId: safeString(playlistId),
    );
  }

  // Drift'ten VodStream oluşturmak için
  factory VodStream.fromDriftVodStream(VodStreamsData driftVodStream) {
    return VodStream(
      streamId: driftVodStream.streamId,
      name: driftVodStream.name,
      streamIcon: driftVodStream.streamIcon,
      categoryId: driftVodStream.categoryId,
      rating: driftVodStream.rating,
      rating5based: driftVodStream.rating5based,
      containerExtension: driftVodStream.containerExtension,
      playlistId: driftVodStream.playlistId,
    );
  }

  // Drift'e kaydetmek için
  VodStreamsCompanion toDriftCompanion() {
    return VodStreamsCompanion(
      streamId: Value(streamId),
      name: Value(name),
      streamIcon: Value(streamIcon),
      categoryId: Value(categoryId),
      rating: Value(rating),
      rating5based: Value(rating5based),
      containerExtension: Value(containerExtension),
      playlistId: Value(playlistId ?? ''),
    );
  }
}
