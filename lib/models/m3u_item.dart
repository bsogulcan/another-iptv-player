import 'package:another_iptv_player/models/content_type.dart';

class M3uItem {
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
    this.categoryId
  });

  @override
  String toString() {
    return 'M3uItem(name: $name, url: $url, userAgent: $userAgent, referrer: $referrer, groupTitle: $groupTitle)';
  }
}
