import 'package:another_iptv_player/models/server_info.dart';
import 'package:another_iptv_player/models/user_info.dart';

class ApiResponse {
  final UserInfo userInfo;
  final ServerInfo serverInfo;
  final String playlistId;

  ApiResponse({
    required this.userInfo,
    required this.serverInfo,
    required this.playlistId,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json, String playlistId) {
    return ApiResponse(
      playlistId: playlistId,
      userInfo: UserInfo.fromJson(json['user_info'] ?? {}, playlistId),
      serverInfo: ServerInfo.fromJson(json['server_info'] ?? {}, playlistId),
    );
  }
}
