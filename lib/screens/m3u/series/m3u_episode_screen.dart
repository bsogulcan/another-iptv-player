import 'dart:async';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/models/m3u_series.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/watch_history.dart';
import '../../../models/content_type.dart';
import '../../../services/event_bus.dart';
import '../../../widgets/loading_widget.dart';
import '../../../widgets/player_widget.dart';
import '../../../controllers/favorites_controller.dart';
import '../../../models/favorite.dart';

class M3uEpisodeScreen extends StatefulWidget {
  final List<int> seasons;
  final List<M3uEpisode> episodes;
  final ContentItem contentItem;
  final WatchHistory? watchHistory;

  const M3uEpisodeScreen({
    super.key,
    required this.seasons,
    required this.episodes,
    required this.contentItem,
    this.watchHistory,
  });

  @override
  State<M3uEpisodeScreen> createState() => _M3uEpisodeScreenState();
}

class _M3uEpisodeScreenState extends State<M3uEpisodeScreen> {
  late ContentItem contentItem;
  List<ContentItem> allContents = [];
  bool allContentsLoaded = false;
  int selectedContentItemIndex = 0;
  late StreamSubscription contentItemIndexChangedSubscription;
  final ScrollController _scrollController = ScrollController();
  late FavoritesController _favoritesController;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    contentItem = widget.contentItem;
    _favoritesController = FavoritesController();
    _initializeQueue();
    _checkFavoriteStatus();
  }

  @override
  void dispose() {
    contentItemIndexChangedSubscription.cancel();
    _scrollController.dispose();
    _favoritesController.dispose();
    super.dispose();
  }

  Future<void> _checkFavoriteStatus() async {
    final isFavorite = await _favoritesController.isFavorite(
      contentItem.id,
      contentItem.contentType,
    );
    if (mounted) {
      setState(() {
        _isFavorite = isFavorite;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final result = await _favoritesController.toggleFavorite(contentItem);
    if (mounted) {
      setState(() {
        _isFavorite = result;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result ? context.loc.added_to_favorites : context.loc.removed_from_favorites,
          ),
        ),
      );
    }
  }

  Future<void> _initializeQueue() async {
    allContents = widget.episodes
        .where((x) {
          return x.seasonNumber == widget.contentItem.season;
        })
        .map((x) {
          return ContentItem(
            x.url,
            x.name,
            x.cover ?? "",
            ContentType.series,
            season: x.seasonNumber,
          );
        })
        .toList();

    setState(() {
      selectedContentItemIndex = allContents.indexWhere(
        (element) => element.id == widget.contentItem.id,
      );
      allContentsLoaded = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelectedItem();
      });
    });

    contentItemIndexChangedSubscription = EventBus()
        .on<int>('player_content_item_index')
        .listen((int index) {
          if (!mounted) return;

          setState(() {
            selectedContentItemIndex = index;
            contentItem = allContents[selectedContentItemIndex];
          });
          
          _checkFavoriteStatus();
        });
  }

  void _scrollToSelectedItem() {
    if (_scrollController.hasClients && selectedContentItemIndex >= 0) {
      final double itemHeight = 110.0;
      final double scrollOffset = selectedContentItemIndex * itemHeight;

      _scrollController.animateTo(
        scrollOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  _onContentTap(ContentItem contentItem) {
    setState(() {
      if (!mounted) return;

      selectedContentItemIndex = allContents.indexOf(contentItem);
    });
    EventBus().emit(
      'player_content_item_index_changed',
      selectedContentItemIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!allContentsLoaded) {
      return buildFullScreenLoadingWidget();
    } else {
      return Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PlayerWidget(contentItem: widget.contentItem, queue: allContents),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 5, 0, 0),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        contentItem.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: _toggleFavorite,
                                      icon: Icon(
                                        _isFavorite ? Icons.favorite : Icons.favorite_border,
                                        color: _isFavorite ? Colors.red : Colors.grey,
                                        size: 28,
                                      ),
                                    ),
                                    Text(
                                      context.loc.episode_count(
                                        allContents.length,
                                      ),
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: allContents.isEmpty
                                    ? Center(
                                        child: Text(
                                          context.loc.not_found_in_category,
                                        ),
                                      )
                                    : ListView.builder(
                                        controller: _scrollController,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        itemCount: allContents.length,
                                        itemBuilder: (context, index) {
                                          final episode = widget.episodes.where(
                                            (x) {
                                              return x.url ==
                                                  allContents[index].id;
                                            },
                                          ).first;
                                          return _buildEpisodeCard(
                                            episode,
                                            index,
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildEpisodeCard(M3uEpisode episode, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selectedContentItemIndex == index
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _onContentTap(allContents[index]);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: episode.cover != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          episode.cover!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                '${episode.episodeNumber}.${context.loc.episode_short}',
                                style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : Center(
                        child: Text(
                          '${episode.episodeNumber}.${context.loc.episode_short}',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      episode.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
