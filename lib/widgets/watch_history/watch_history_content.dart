import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/models/watch_history.dart';
import 'package:another_iptv_player/widgets/watch_history/watch_history_app_bar_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:another_iptv_player/utils/responsive_helper.dart';
import '../../controllers/watch_history_controller.dart';
import '../../controllers/favorites_controller.dart';
import '../../models/favorite.dart';
import 'watch_history_section.dart';
import 'favorites_section.dart';

class WatchHistoryContent extends StatelessWidget {
  final Function(dynamic) onHistoryTap;
  final Function(dynamic) onHistoryRemove;
  final Function(String, List<WatchHistory>) onSeeAllTap;
  final Function(Favorite)? onFavoriteRemove;
  final VoidCallback? onSeeAllFavorites;

  const WatchHistoryContent({
    super.key,
    required this.onHistoryTap,
    required this.onHistoryRemove,
    required this.onSeeAllTap,
    this.onFavoriteRemove,
    this.onSeeAllFavorites,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<WatchHistoryController>(
      builder: (context, controller, child) {
        final cardWidth = ResponsiveHelper.getCardWidth(context);
        final cardHeight = ResponsiveHelper.getCardHeight(context);

        return NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              WatchHistoryAppBar(
                onRefresh: controller.loadWatchHistory,
                onClearAll: controller.clearAllHistory,
                onRefreshFavorites: () {
                  final favoritesController = context.read<FavoritesController>();
                  favoritesController.loadFavorites();
                },
              ),
            ];
          },
          body: SingleChildScrollView(
            child: Column(
              children: [
                Consumer<FavoritesController>(
                  builder: (context, favoritesController, child) {
                    return FavoritesSection(
                      favorites: favoritesController.favorites,
                      cardWidth: cardWidth,
                      cardHeight: cardHeight,
                      onSeeAllTap: onSeeAllFavorites,
                      onFavoriteRemove: onFavoriteRemove,
                    );
                  },
                ),
                WatchHistorySection(
                  title: context.loc.live_streams,
                  histories: controller.liveHistory,
                  cardWidth: cardWidth,
                  cardHeight: cardHeight,
                  onHistoryTap: onHistoryTap,
                  onHistoryRemove: onHistoryRemove,
                  onSeeAllTap: () => onSeeAllTap(
                    context.loc.live_streams,
                    controller.liveHistory,
                  ),
                ),
                WatchHistorySection(
                  title: context.loc.movies,
                  histories: controller.movieHistory,
                  cardWidth: cardWidth,
                  cardHeight: cardHeight,
                  showProgress: true,
                  onHistoryTap: onHistoryTap,
                  onHistoryRemove: onHistoryRemove,
                  onSeeAllTap: () =>
                      onSeeAllTap(context.loc.movies, controller.movieHistory),
                ),
                WatchHistorySection(
                  title: context.loc.series_plural,
                  histories: controller.seriesHistory,
                  cardWidth: cardWidth,
                  cardHeight: cardHeight,
                  showProgress: true,
                  onHistoryTap: onHistoryTap,
                  onHistoryRemove: onHistoryRemove,
                  onSeeAllTap: () => onSeeAllTap(
                    context.loc.series_plural,
                    controller.seriesHistory,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }
}
