import 'package:another_iptv_player/models/content_type.dart';
import 'package:drift/drift.dart';
import 'package:another_iptv_player/database/database.dart';

class Favorite {
  final String id;
  final String playlistId;
  final ContentType contentType;
  final String streamId;
  final String? episodeId;
  final String? m3uItemId;
  final String name;
  final String? imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  Favorite({
    required this.id,
    required this.playlistId,
    required this.contentType,
    required this.streamId,
    this.episodeId,
    this.m3uItemId,
    required this.name,
    this.imagePath,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Favorite.fromDrift(FavoritesData driftObject) {
    return Favorite(
      id: driftObject.id,
      playlistId: driftObject.playlistId,
      contentType: ContentType.values[driftObject.contentType],
      streamId: driftObject.streamId,
      episodeId: driftObject.episodeId,
      m3uItemId: driftObject.m3uItemId,
      name: driftObject.name,
      imagePath: driftObject.imagePath,
      createdAt: driftObject.createdAt,
      updatedAt: driftObject.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'playlist_id': playlistId,
      'content_type': contentType.index,
      'stream_id': streamId,
      'episode_id': episodeId,
      'm3u_item_id': m3uItemId,
      'name': name,
      'image_path': imagePath,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  FavoritesCompanion toCompanion() {
    return FavoritesCompanion(
      id: Value(id),
      playlistId: Value(playlistId),
      contentType: Value(contentType.index),
      streamId: Value(streamId),
      episodeId: Value(episodeId),
      m3uItemId: Value(m3uItemId),
      name: Value(name),
      imagePath: Value(imagePath),
      updatedAt: Value(DateTime.now()),
    );
  }

  @override
  String toString() {
    return 'Favorite(id: $id, playlistId: $playlistId, contentType: $contentType, streamId: $streamId, episodeId: $episodeId, m3uItemId: $m3uItemId, name: $name)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Favorite &&
        other.id == id &&
        other.playlistId == playlistId &&
        other.contentType == contentType &&
        other.streamId == streamId &&
        other.episodeId == episodeId &&
        other.m3uItemId == m3uItemId;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      playlistId.hashCode ^
      contentType.hashCode ^
      streamId.hashCode ^
      episodeId.hashCode ^
      m3uItemId.hashCode;
} 