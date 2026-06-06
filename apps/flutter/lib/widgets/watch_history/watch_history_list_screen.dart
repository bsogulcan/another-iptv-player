import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/widgets/watch_history/watch_history_card.dart';
import 'package:flutter/material.dart';
import '../../models/watch_history.dart';
import '../../utils/responsive_helper.dart';

class WatchHistoryListScreen extends StatelessWidget {
  final String title;
  final List<WatchHistory> histories;
  final void Function(WatchHistory)? onHistoryTap;
  final void Function(WatchHistory)? onHistoryRemove;

  const WatchHistoryListScreen({
    super.key,
    required this.title,
    required this.histories,
    this.onHistoryTap,
    this.onHistoryRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cardWidth = ResponsiveHelper.getCardWidth(context);
    final cardHeight = ResponsiveHelper.getCardHeight(context);
    final crossAxisCount = ResponsiveHelper.getCrossAxisCount(context);

    return Scaffold(
      appBar: AppBar(title: Text(title), elevation: 0),
      body: histories.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    context.loc.not_found_in_category,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: cardWidth / cardHeight,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: histories.length,
              itemBuilder: (context, index) {
                final history = histories[index];
                return WatchHistoryCard(
                  history: history,
                  width: cardWidth,
                  height: cardHeight,
                  showProgress:
                      title == 'Devam Et' ||
                      title == 'Filmler' ||
                      title == 'Diziler',
                  onTap: () => onHistoryTap?.call(history),
                  onRemove: () => onHistoryRemove?.call(history),
                );
              },
            ),
    );
  }
}
