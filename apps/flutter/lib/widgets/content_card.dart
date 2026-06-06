import 'package:another_iptv_player/l10n/localization_extension.dart';
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
    bool isRecent = false;
    String? releaseDateStr;
    DateTime? releaseDate;

    if (content.contentType == ContentType.series) {
      releaseDateStr = content.seriesStream?.releaseDate;
    }

    if (releaseDateStr != null && releaseDateStr.isNotEmpty) {
      try {
        releaseDate = DateTime.parse(releaseDateStr);
      } catch (e) {
        releaseDate = null;
      }
    }

    if (releaseDate != null) {
      final diff = DateTime.now().difference(releaseDate).inDays;
      isRecent = diff <= 15;
    }

    final bool isLiveStream = content.contentType == ContentType.liveStream;
    final Widget? ratingBadge =
    isLiveStream ? null : _buildRatingBadge(context);

    Widget cardWidget = Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 1),
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
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
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) =>
                          _buildTitleCard(context),
                    )
                        : _buildTitleCard(context),
                  ),
                  if (ratingBadge != null) ratingBadge,
                  if (isRecent)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.loc.new_ep,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
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
    if (content.contentType == ContentType.liveStream) {
      return BoxFit.contain;
    }
    return BoxFit.cover;
  }

  Widget _buildTitleCard(BuildContext context) {
    return Container(
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(6),
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

  Widget? _buildRatingBadge(BuildContext context) {
    final dynamic rawRating = content.contentType == ContentType.series
        ? content.seriesStream?.rating
        : content.vodStream?.rating;

    final double? rating = _parseRating(rawRating);
    if (rating == null || rating <= 0) {
      return null;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final formattedRating = rating % 1 == 0
        ? rating.toStringAsFixed(0)
        : rating.toStringAsFixed(1);

    return Positioned(
      top: 6,
      right: 6,
      child: Semantics(
        label: 'Rating $formattedRating',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.secondaryContainer.withOpacity(0.93),
                colorScheme.secondary.withOpacity(0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.onSecondaryContainer.withOpacity(0.16),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.22),
                offset: const Offset(0, 1),
                blurRadius: 4,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.star_rounded,
                size: 14,
                color: colorScheme.onSecondaryContainer.withOpacity(0.9),
              ),
              const SizedBox(width: 3),
              Text(
                formattedRating,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                  color: colorScheme.onSecondaryContainer,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double? _parseRating(dynamic rating) {
    if (rating == null) return null;
    if (rating is num) return rating.toDouble();
    if (rating is String && rating.isNotEmpty) {
      final normalized = rating.replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    return null;
  }
}