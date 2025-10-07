import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/content_type.dart';


class ContentCard extends StatelessWidget {
  final ContentItem content;
  final double width;
  final VoidCallback? onTap;
  final bool isSelected;

  const ContentCard({
    super.key,
    required this.content,
    required this.width,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget cardWidget = Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.fromLTRB(0, 0, 0, 1),
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : null, // null = default card color
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: content.imagePath.isNotEmpty
                        ? CachedNetworkImage(
                      imageUrl: content.imagePath,
                      fit: _getFitForContentType(),
                      placeholder: (context, url) => Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => _buildTitleCard(context),
                    )
                        : _buildTitleCard(context),
                  ),
                  if (content.contentType != ContentType.liveStream)
                    Builder(
                      builder: (context) {
                        final rating = content.contentType == ContentType.series
                            ? content.seriesStream?.rating
                            : content.vodStream?.rating;
                        if (rating != null && rating.toString().isNotEmpty) {
                          return Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                rating.toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          );
                        } else {
                          return const SizedBox.shrink();
                        }
                      },
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      color: Colors.black.withOpacity(0.7),
                      child: Text(
                        content.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return cardWidget;
  }

  BoxFit _getFitForContentType() {
    // Canlı yayınlar için contain kullan (logolar için)
    if (content.contentType == ContentType.liveStream) {
      return BoxFit.contain;
    }
    // Film ve diziler için cover kullan (posterler için)
    return BoxFit.cover;
  }

  Widget _buildTitleCard(BuildContext context) {
    return Container(
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(6),
          child: Text(
            content.name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: isSelected
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : null,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
