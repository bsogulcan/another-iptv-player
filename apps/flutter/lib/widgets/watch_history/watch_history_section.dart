import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/widgets/watch_history/watch_history_card.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/watch_history.dart';

class WatchHistorySection extends StatelessWidget {
  final String title;
  final List<WatchHistory> histories;
  final double cardWidth;
  final double cardHeight;
  final bool showProgress;
  final Function(WatchHistory)? onHistoryTap;
  final Function(WatchHistory)? onHistoryRemove;
  final VoidCallback? onSeeAllTap;

  const WatchHistorySection({
    super.key,
    required this.title,
    required this.histories,
    required this.cardWidth,
    required this.cardHeight,
    this.showProgress = false,
    this.onHistoryTap,
    this.onHistoryRemove,
    this.onSeeAllTap,
  });

  @override
  Widget build(BuildContext context) {
    if (histories.isEmpty) {
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (onSeeAllTap != null && histories.length > 5)
                TextButton(
                  onPressed: onSeeAllTap,
                  child: Text(context.loc.see_all),
                ),
            ],
          ),
        ),
        SizedBox(
          height: cardHeight + 16,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 12),
            itemCount: histories.length > 10 ? 10 : histories.length,
            itemBuilder: (context, index) {
              final history = histories[index];
              return WatchHistoryCard(
                history: history,
                width: cardWidth,
                height: cardHeight,
                showProgress: showProgress,
                onTap: () => onHistoryTap?.call(history),
                onRemove: () => onHistoryRemove?.call(history),
              );
            },
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }
}
