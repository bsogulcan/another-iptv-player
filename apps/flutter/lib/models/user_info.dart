import 'package:another_iptv_player/utils/type_convertions.dart';

class UserInfo {
  final int? id;
  final String playlistId;
  final String username;
  final String password;
  final String message;
  final int auth;
  final String status;
  final String expDate;
  final String isTrial;
  final String activeCons;
  final String createdAt;
  final String maxConnections;
  final List<String> allowedOutputFormats;

  UserInfo({
    this.id,
    required this.playlistId,
    required this.username,
    required this.password,
    required this.message,
    required this.auth,
    required this.status,
    required this.expDate,
    required this.isTrial,
    required this.activeCons,
    required this.createdAt,
    required this.maxConnections,
    required this.allowedOutputFormats,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json, String playlistId) {
    return UserInfo(
      playlistId: safeString(playlistId),
      username: safeString(json['username']),
      password: safeString(json['password']),
      message: safeString(json['message']),
      auth: safeInt(json['auth']),
      status: safeString(json['status']),
      expDate: safeString(json['exp_date']),
      isTrial: safeString(json['is_trial']),
      activeCons: safeString(json['active_cons']),
      createdAt: safeString(json['created_at']),
      maxConnections: safeString(json['max_connections']),
      allowedOutputFormats: json['allowed_output_formats'] is List
          ? (json['allowed_output_formats'] as List)
                .map((e) => safeString(e))
                .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'playlistId': playlistId,
      'username': username,
      'password': password,
      'message': message,
      'auth': auth,
      'status': status,
      'expDate': expDate,
      'isTrial': isTrial,
      'activeCons': activeCons,
      'createdAt': createdAt,
      'maxConnections': maxConnections,
      'allowedOutputFormats': allowedOutputFormats,
    };
  }
}
