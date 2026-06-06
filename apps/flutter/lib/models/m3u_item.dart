import 'package:another_iptv_player/models/content_type.dart';
import 'package:drift/drift.dart';

import '../database/database.dart';

class M3uItem {
  final String id;
  final String playlistId;
  final String? name;
  final String? tvgId;
  final String? tvgName;
  final String? tvgLogo;
  final String? tvgUrl;
  final String? tvgRec;
  final String? tvgShift;
  final String? groupTitle;
  final String? groupName;
  final String? userAgent;
  final String? referrer;
  final String url;
  final ContentType contentType;
  String? categoryId;

  M3uItem({
    required this.id,
    required this.playlistId,
    required this.url,
    required this.contentType,
    this.name,
    this.tvgId,
    this.tvgName,
    this.tvgLogo,
    this.tvgUrl,
    this.tvgRec,
    this.tvgShift,
    this.groupTitle,
    this.groupName,
    this.userAgent,
    this.referrer,
    this.categoryId,
  });

  @override
  String toString() {
    return 'M3uItem(name: $name, url: $url, userAgent: $userAgent, referrer: $referrer, groupTitle: $groupTitle)';
  }

  M3uItemsCompanion toCompanion() {
    return M3uItemsCompanion(
      id: Value(id),
      playlistId: Value(playlistId),
      name: Value(name),
      tvgId: Value(tvgId),
      tvgName: Value(tvgName),
      tvgLogo: Value(tvgLogo),
      tvgUrl: Value(tvgUrl),
      tvgRec: Value(tvgRec),
      tvgShift: Value(tvgShift),
      groupTitle: Value(groupTitle),
      groupName: Value(groupName),
      userAgent: Value(userAgent),
      referrer: Value(referrer),
      url: Value(url),
      contentType: Value(contentType.index),
      categoryId: Value(categoryId),
    );
  }

  factory M3uItem.fromData(M3uItemData data) {
    return M3uItem(
      id: data.id,
      playlistId: data.playlistId,
      url: data.url,
      contentType: ContentType.values[data.contentType],
      name: data.name,
      tvgId: data.tvgId,
      tvgName: data.tvgName,
      tvgLogo: data.tvgLogo,
      tvgUrl: data.tvgUrl,
      tvgRec: data.tvgRec,
      tvgShift: data.tvgShift,
      groupTitle: data.groupTitle,
      groupName: data.groupName,
      userAgent: data.userAgent,
      referrer: data.referrer,
      categoryId: data.categoryId,
    );
  }

  M3uItem copyWith({
    String? id,
    String? playlistId,
    String? name,
    String? tvgId,
    String? tvgName,
    String? tvgLogo,
    String? tvgUrl,
    String? tvgRec,
    String? tvgShift,
    String? groupTitle,
    String? groupName,
    String? userAgent,
    String? referrer,
    String? url,
    ContentType? contentType,
    String? categoryId,
  }) {
    return M3uItem(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      name: name ?? this.name,
      tvgId: tvgId ?? this.tvgId,
      tvgName: tvgName ?? this.tvgName,
      tvgLogo: tvgLogo ?? this.tvgLogo,
      tvgUrl: tvgUrl ?? this.tvgUrl,
      tvgRec: tvgRec ?? this.tvgRec,
      tvgShift: tvgShift ?? this.tvgShift,
      groupTitle: groupTitle ?? this.groupTitle,
      groupName: groupName ?? this.groupName,
      userAgent: userAgent ?? this.userAgent,
      referrer: referrer ?? this.referrer,
      url: url ?? this.url,
      contentType: contentType ?? this.contentType,
      categoryId: categoryId ?? this.categoryId,
    );
  }
}
