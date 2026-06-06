import 'package:flutter/material.dart';
import '../../../../models/playlist_model.dart';

class PlaylistUtils {
  static Color getPlaylistColor(PlaylistType type) {
    return switch (type) {
      PlaylistType.xtream => Colors.blue,
      PlaylistType.m3u => Colors.green,
    };
  }

  static IconData getPlaylistIcon(PlaylistType type) {
    return switch (type) {
      PlaylistType.xtream => Icons.stream,
      PlaylistType.m3u => Icons.playlist_play,
    };
  }

  static String formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Bugün';
    } else if (difference.inDays == 1) {
      return 'Dün';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} gün önce';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }
}