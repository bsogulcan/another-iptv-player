import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/watch_history.dart';

class WatchHistoryCard extends StatelessWidget {
  final WatchHistory history;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final bool showProgress;

  const WatchHistoryCard({
    super.key,
    required this.history,
    required this.width,
    required this.height,
    this.onTap,
    this.onRemove,
    this.showProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: EdgeInsets.symmetric(horizontal: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // Background/Thumbnail
              _buildThumbnail(),

              // Remove Button
              if (onRemove != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ),

              // Progress Bar (if applicable)
              if (showProgress &&
                  history.watchDuration != null &&
                  history.totalDuration != null)
                Positioned(
                  bottom: 30,
                  left: 8,
                  right: 8,
                  child: _buildProgressBar(),
                ),

              // Content Info
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        history.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    if (history.imagePath != null && history.imagePath!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: history.imagePath!,
        width: double.infinity,
        height: double.infinity,
        fit: _getFitForContentType(),
        placeholder: (context, url) => Container(
          color: Colors.grey[300],
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (context, url, error) => _buildDefaultThumbnail(),
      );
    } else {
      return _buildDefaultThumbnail();
    }
  }

  BoxFit _getFitForContentType() {
    // Canlı yayınlar için contain kullan (logolar için)
    if (history.contentType == ContentType.liveStream) {
      return BoxFit.contain;
    }
    // Film ve diziler için cover kullan (posterler için)
    return BoxFit.cover;
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _getContentTypeColor(history.contentType).withOpacity(0.8),
            _getContentTypeColor(history.contentType),
          ],
        ),
      ),
      child: Icon(
        _getContentTypeIcon(history.contentType),
        size: 48,
        color: Colors.white,
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = history.totalDuration!.inMilliseconds.isInfinite
        ? 0.0
        : (history.watchDuration!.inMilliseconds /
              history.totalDuration!.inMilliseconds);

    return Column(
      children: [
        LinearProgressIndicator(
          value: progress.isInfinite || progress.isNaN ? 0 : progress,
          backgroundColor: Colors.white30,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          minHeight: 3,
        ),
        SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(history.watchDuration!),
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
            Text(
              _formatDuration(history.totalDuration!),
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  Color _getContentTypeColor(ContentType type) {
    switch (type) {
      case ContentType.liveStream:
        return Colors.red;
      case ContentType.vod:
        return Colors.blue;
      case ContentType.series:
        return Colors.green;
    }
  }

  IconData _getContentTypeIcon(ContentType type) {
    switch (type) {
      case ContentType.liveStream:
        return Icons.live_tv;
      case ContentType.vod:
        return Icons.movie;
      case ContentType.series:
        return Icons.tv;
    }
  }

  String _getContentTypeText(ContentType type) {
    switch (type) {
      case ContentType.liveStream:
        return 'CANLI';
      case ContentType.vod:
        return 'FİLM';
      case ContentType.series:
        return 'DİZİ';
    }
  }

  String _formatLastWatched(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}g önce';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}s önce';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}dk önce';
    } else {
      return 'Az önce';
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    } else {
      return "$twoDigitMinutes:$twoDigitSeconds";
    }
  }
}
