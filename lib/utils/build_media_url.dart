import 'package:another_iptv_player/services/app_state.dart';

import '../models/content_type.dart';
import '../models/playlist_content_model.dart';

String buildMediaUrl(ContentItem contentItem) {
  var playlist = AppState.currentPlaylist!;
  switch (contentItem.contentType) {
    case ContentType.liveStream:
      return '${playlist.url}/${playlist.username}/${playlist.password}/${contentItem.id}';
    case ContentType.vod:
      return '${playlist.url}/movie/${playlist.username}/${playlist.password}/${contentItem.id}.${contentItem.containerExtension}';
    case ContentType.series:
      return '${playlist.url}/series/${playlist.username}/${playlist.password}/${contentItem.id}.${contentItem.containerExtension}';
  }
}
