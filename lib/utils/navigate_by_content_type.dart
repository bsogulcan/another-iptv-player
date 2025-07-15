import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import '../screens/live_stream/live_stream_screen.dart';
import '../screens/movies/movie_screen.dart';
import '../screens/series/series_screen.dart';

void navigateByContentType(BuildContext context, ContentItem content) {
  switch (content.contentType) {
    case ContentType.liveStream:
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LiveStreamScreen(content: content),
        ),
      );
    case ContentType.vod:
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MovieScreen(contentItem: content),
        ),
      );
    case ContentType.series:
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SeriesScreen(contentItem: content),
        ),
      );
  }
}