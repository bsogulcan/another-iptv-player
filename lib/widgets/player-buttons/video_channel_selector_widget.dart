import 'dart:async';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/event_bus.dart';
import 'package:another_iptv_player/services/player_state.dart';
import 'package:another_iptv_player/services/playlist_content_state.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:flutter/material.dart';
import '../../models/content_type.dart';
import '../../utils/get_playlist_type.dart';

class VideoChannelSelectorWidget extends StatefulWidget {
  final List<ContentItem>? queue;
  final int? currentIndex;

  const VideoChannelSelectorWidget({super.key, this.queue, this.currentIndex});

  @override
  State<VideoChannelSelectorWidget> createState() =>
      _VideoChannelSelectorWidgetState();

  static void hideOverlay() {
    _VideoChannelSelectorWidgetState.hideOverlay();
  }
}

class _VideoChannelSelectorWidgetState
    extends State<VideoChannelSelectorWidget> {
  static OverlayEntry? _globalOverlayEntry;
  static StreamSubscription? _globalIndexSubscription;
  static StreamSubscription? _globalToggleSubscription;
  static BuildContext? _globalContext;
  static String? _selectedCategoryId;
  static bool _showCategories = false;
  static int? _selectedSeason;
  static bool _showSeasons = false;
  static ScrollController? _categoriesScrollController;
  static ScrollController? _channelsScrollController;
  static void hideOverlay() {
    _globalOverlayEntry?.remove();
    _globalOverlayEntry = null;
    _globalIndexSubscription?.cancel();
    _globalIndexSubscription = null;
    _categoriesScrollController?.dispose();
    _categoriesScrollController = null;
    _channelsScrollController?.dispose();
    _channelsScrollController = null;
    _selectedCategoryId = null;
    _showCategories = false;
    _selectedSeason = null;
    _showSeasons = false;
    PlayerState.showChannelList = false;
  }

  @override
  void initState() {
    super.initState();

    _globalContext = context;

    if (_globalToggleSubscription == null) {
      _globalToggleSubscription = EventBus()
          .on<bool>('toggle_channel_list')
          .listen((bool show) {
            if (show) {
              if (_globalContext != null) {
                _showChannelSelector(_globalContext!);
              }
            } else {
              _hideChannelSelector();
            }
          });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isM3u) {
      return const SizedBox.shrink();
    }

    if (widget.queue == null || widget.queue!.length <= 1) {
      return const SizedBox.shrink();
    }

    _globalContext = context;

    final currentContent = PlayerState.currentContent;
    String tooltip = context.loc.select_channel;
    if (currentContent?.contentType == ContentType.vod) {
      tooltip = context.loc.movies;
    } else if (currentContent?.contentType == ContentType.series) {
      tooltip = context.loc.episodes;
    }

    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.list, color: Colors.white),
      onPressed: () {
        if (_globalOverlayEntry == null) {
          _showChannelSelector(context);
        } else {
          _hideChannelSelector();
        }
      },
    );
  }

  void _showChannelSelector(BuildContext context) async {
    if (_globalOverlayEntry != null) return;

    // Scroll controller'ları oluştur veya yenile
    _categoriesScrollController?.dispose();
    _channelsScrollController?.dispose();
    _categoriesScrollController = ScrollController();
    _channelsScrollController = ScrollController();

    final currentContent = PlayerState.currentContent;
    
    if (currentContent?.contentType == ContentType.liveStream) {
      if (PlaylistContentState.liveCategories.isEmpty) {
        await PlaylistContentState.loadLiveStreams();
      }
      
      String? currentCategoryId;
      if (currentContent?.liveStream != null) {
        currentCategoryId = currentContent!.liveStream!.categoryId;
      } else if (currentContent?.m3uItem != null) {
        currentCategoryId = currentContent!.m3uItem!.categoryId;
      }
      
      if (currentCategoryId != null && 
          PlaylistContentState.liveCategories.any((c) => c.categoryId == currentCategoryId)) {
        _selectedCategoryId = currentCategoryId;
        _showCategories = false;
      } else {
        _showCategories = true;
        _selectedCategoryId = null;
      }
      _showSeasons = false;
      _selectedSeason = null;
    } else if (currentContent?.contentType == ContentType.series) {
      final items = widget.queue ?? [];
      if (items.isEmpty) return;
      
      final currentSeason = currentContent?.season;
      
      if (currentSeason != null) {
        _selectedSeason = currentSeason;
        _showSeasons = false;
      } else {
        _showSeasons = true;
        _selectedSeason = null;
      }
      _showCategories = false;
      _selectedCategoryId = null;
    } else {
      final items = widget.queue ?? [];
      if (items.isEmpty) return;
      _showCategories = false;
      _showSeasons = false;
      _selectedCategoryId = null;
      _selectedSeason = null;
    }

    final overlayContext = _globalContext ?? context;

    OverlayState? overlay;
    try {
      overlay = Overlay.of(overlayContext, rootOverlay: true);
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_globalOverlayEntry == null) {
          _showChannelSelector(overlayContext);
        }
      });
      return;
    }

    final screenWidth = MediaQuery.of(overlayContext).size.width;
    final panelWidth = (screenWidth / 3).clamp(200.0, 400.0);

    _globalOverlayEntry = OverlayEntry(
      opaque: false,
      maintainState: true,
      builder: (context) => _buildOverlay(context, panelWidth),
    );

    overlay.insert(_globalOverlayEntry!);
    PlayerState.showChannelList = true;

    _globalIndexSubscription?.cancel();
    _globalIndexSubscription = EventBus()
        .on<int>('player_content_item_index')
        .listen((int index) {
          if (_globalOverlayEntry != null) {
            _globalOverlayEntry!.markNeedsBuild();
          }
        });
  }

  void _hideChannelSelector() {
    _globalOverlayEntry?.remove();
    _globalOverlayEntry = null;
    _globalIndexSubscription?.cancel();
    _globalIndexSubscription = null;
    PlayerState.showChannelList = false;
  }

  Widget _buildOverlay(
    BuildContext context,
    double panelWidth,
  ) {
    if (_globalOverlayEntry == null) {
      return const SizedBox.shrink();
    }

    final backgroundColor = Colors.black.withOpacity(0.95);
    final cardColor = Colors.black.withOpacity(0.8);
    const textColor = Colors.white;
    const secondaryTextColor = Colors.grey;
    final dividerColor = Colors.grey[800]!;

    final currentContent = PlayerState.currentContent;
    final isLiveStream = currentContent?.contentType == ContentType.liveStream;
    final isSeries = currentContent?.contentType == ContentType.series;
    final isVod = currentContent?.contentType == ContentType.vod;

    List<ContentItem> items = [];
    int? selectedIndex;
    
    if (_showCategories && isLiveStream) {
    } else if (_selectedCategoryId != null && isLiveStream) {
      items = PlaylistContentState.getLiveStreamsByCategory(_selectedCategoryId!);
      if (currentContent != null) {
        final foundIndex = items.indexWhere(
          (item) => item.id == currentContent.id,
        );
        if (foundIndex != -1) {
          selectedIndex = foundIndex;
        }
      }
    } else if (_showSeasons && isSeries) {
    } else if (_selectedSeason != null && isSeries) {
      final allItems = widget.queue ?? [];
      items = allItems.where((item) => item.season == _selectedSeason).toList();
      if (currentContent != null) {
        final foundIndex = items.indexWhere(
          (item) => item.id == currentContent.id,
        );
        if (foundIndex != -1) {
          selectedIndex = foundIndex;
        }
      }
    } else {
      if (isSeries && _selectedSeason != null) {
        final allItems = widget.queue ?? [];
        items = allItems.where((item) => item.season == _selectedSeason).toList();
      } else {
        items = widget.queue ?? [];
      }
      if (currentContent != null) {
        final foundIndex = items.indexWhere(
          (item) => item.id == currentContent.id,
        );
        if (foundIndex != -1) {
          selectedIndex = foundIndex;
        }
      }
      if (selectedIndex == null) {
        selectedIndex = widget.currentIndex ?? 0;
      }
    }

    return Positioned.fill(
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: backgroundColor,
          elevation: 8,
          child: Container(
            width: panelWidth,
            height: double.infinity,
            decoration: BoxDecoration(
              color: backgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    border: Border(
                      bottom: BorderSide(color: dividerColor, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      if ((_selectedCategoryId != null && isLiveStream) || 
                          (_selectedSeason != null && isSeries))
                        IconButton(
                          icon: Icon(Icons.arrow_back, color: textColor, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            if (isLiveStream) {
                              _selectedCategoryId = null;
                              _showCategories = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _categoriesScrollController?.animateTo(
                                  0,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              });
                            } else if (isSeries) {
                              _selectedSeason = null;
                              _showSeasons = true;
                            }
                            _globalOverlayEntry?.markNeedsBuild();
                          },
                        ),
                      Expanded(
                        child: Text(
                          _showCategories && isLiveStream
                              ? context.loc.categories
                              : _selectedCategoryId != null && isLiveStream
                                  ? PlaylistContentState.liveCategories
                                      .firstWhere((c) => c.categoryId == _selectedCategoryId)
                                      .categoryName
                                      : _showSeasons && isSeries
                                          ? context.loc.seasons
                                          : _selectedSeason != null && isSeries
                                              ? context.loc.season_number_format(_selectedSeason!)
                                              : isVod
                                                  ? context.loc.movies
                                                  : isSeries
                                                      ? context.loc.episodes
                                                      : context.loc.select_channel,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                      if ((!_showCategories || _selectedCategoryId != null) && 
                          (!_showSeasons || _selectedSeason != null) && 
                          selectedIndex != null)
                        Text(
                          '${selectedIndex + 1} / ${items.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.close, color: textColor, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _hideChannelSelector,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _showCategories && isLiveStream
                      ? _buildCategoriesList(context)
                      : _showSeasons && isSeries
                          ? _buildSeasonsList(context)
                          : ListView.builder(
                              controller: _channelsScrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final isSelected = selectedIndex != null && index == selectedIndex;

                                return _buildChannelListItem(
                                  context,
                                  item,
                                  index,
                                  isSelected,
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeasonsList(BuildContext context) {
    const textColor = Colors.white;
    const secondaryTextColor = Colors.grey;
    final dividerColor = Colors.grey[800]!;
    final cardBackground = Colors.white.withOpacity(0.05);
    const primaryColor = Colors.blue;
    final primaryContainer = Colors.blue.withOpacity(0.2);

    final allItems = widget.queue ?? [];
    final currentContent = PlayerState.currentContent;
    
    final seasons = allItems
        .where((item) => item.season != null)
        .map((item) => item.season!)
        .toSet()
        .toList()
      ..sort();
    
    final currentSeason = currentContent?.season;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: seasons.length,
      itemBuilder: (context, index) {
        final season = seasons[index];
        final episodeCount = allItems.where((item) => item.season == season).length;
        final isSelected = currentSeason != null && season == currentSeason;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              _selectedSeason = season;
              _showSeasons = false;
              _globalOverlayEntry?.markNeedsBuild();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryContainer.withOpacity(0.3)
                    : cardBackground,
                borderRadius: BorderRadius.circular(8),
                border: isSelected
                    ? Border.all(color: primaryColor, width: 2)
                    : Border.all(color: dividerColor, width: 1),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tv,
                    color: isSelected ? primaryColor : Colors.blue,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.loc.season_number_format(season),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.loc.episode_count_format(episodeCount),
                          style: const TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      color: primaryColor,
                      size: 20,
                    )
                  else
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: secondaryTextColor,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoriesList(BuildContext context) {
    const textColor = Colors.white;
    const secondaryTextColor = Colors.grey;
    final dividerColor = Colors.grey[800]!;
    final cardBackground = Colors.white.withOpacity(0.05);
    const primaryColor = Colors.blue;
    final primaryContainer = Colors.blue.withOpacity(0.2);

    final categories = PlaylistContentState.liveCategories;
    final currentContent = PlayerState.currentContent;
    
    String? currentCategoryId;
    if (currentContent?.liveStream != null) {
      currentCategoryId = currentContent!.liveStream!.categoryId;
    } else if (currentContent?.m3uItem != null) {
      currentCategoryId = currentContent!.m3uItem!.categoryId;
    }

    return ListView.builder(
      controller: _categoriesScrollController,
      padding: const EdgeInsets.all(12),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final channelCount = PlaylistContentState.getLiveStreamsByCategory(category.categoryId).length;
        final isSelected = currentCategoryId != null && category.categoryId == currentCategoryId;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              _selectedCategoryId = category.categoryId;
              _showCategories = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _channelsScrollController?.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              });
              _globalOverlayEntry?.markNeedsBuild();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryContainer.withOpacity(0.3)
                    : cardBackground,
                borderRadius: BorderRadius.circular(8),
                border: isSelected
                    ? Border.all(color: primaryColor, width: 2)
                    : Border.all(color: dividerColor, width: 1),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder,
                    color: isSelected ? primaryColor : Colors.blue,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.categoryName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.loc.channel_count_format(channelCount),
                          style: const TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      color: primaryColor,
                      size: 20,
                    )
                  else
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: secondaryTextColor,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChannelListItem(
    BuildContext context,
    ContentItem item,
    int index,
    bool isSelected,
  ) {
    const textColor = Colors.white;
    const secondaryTextColor = Colors.grey;
    final dividerColor = Colors.grey[800]!;
    const primaryColor = Colors.blue;
    final primaryContainer = Colors.blue.withOpacity(0.2);
    final cardBackground = Colors.white.withOpacity(0.05);
    final errorBackground = Colors.grey[800]!;
    const errorIconColor = Colors.grey;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final isSeries = PlayerState.currentContent?.contentType == ContentType.series;
          
          if (isSeries && item.season != null) {
            if (_selectedSeason != item.season) {
              _selectedSeason = item.season;
              _showSeasons = false;
            }
          }
          
          if (_selectedCategoryId != null && 
              PlayerState.currentContent?.contentType == ContentType.liveStream) {
            final categoryItems = PlaylistContentState.getLiveStreamsByCategory(_selectedCategoryId!);
            PlayerState.queue = categoryItems;
            PlayerState.currentIndex = index;
            PlayerState.currentContent = item;
            
            EventBus().emit('player_content_item_index_changed', index);
            EventBus().emit('player_content_item', item);
          } else {
            final allItems = widget.queue ?? [];
            final realIndex = allItems.indexWhere((queueItem) => queueItem.id == item.id);
            if (realIndex != -1) {
              EventBus().emit('player_content_item_index_changed', realIndex);
            } else {
              EventBus().emit('player_content_item_index_changed', index);
            }
          }
          
          if (isSeries && item.season != null && _selectedSeason == item.season) {
            _globalOverlayEntry?.markNeedsBuild();
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? primaryContainer.withOpacity(0.3)
                : cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: primaryColor, width: 2)
                : Border.all(color: dividerColor, width: 1),
          ),
          child: Row(
            children: [
              if (item.imagePath.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    item.imagePath,
                    width: 50,
                    height: 35,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 50,
                        height: 35,
                        color: errorBackground,
                        child: Icon(
                          Icons.image,
                          color: errorIconColor,
                          size: 20,
                        ),
                      );
                    },
                  ),
                )
              else
                Container(
                  width: 50,
                  height: 35,
                  decoration: BoxDecoration(
                    color: errorBackground,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.video_library,
                    color: errorIconColor,
                    size: 20,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: textColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          _getContentTypeIcon(item.contentType),
                          size: 11,
                          color: secondaryTextColor,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _getContentTypeDisplayName(context, item.contentType),
                            style: TextStyle(
                              fontSize: 11,
                              color: secondaryTextColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: primaryColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getContentTypeIcon(ContentType contentType) {
    switch (contentType) {
      case ContentType.liveStream:
        return Icons.live_tv;
      case ContentType.vod:
        return Icons.movie;
      case ContentType.series:
        return Icons.tv;
    }
  }

  String _getContentTypeDisplayName(BuildContext context, ContentType contentType) {
    switch (contentType) {
      case ContentType.liveStream:
        return context.loc.live_stream_content_type;
      case ContentType.vod:
        return context.loc.movie_content_type;
      case ContentType.series:
        return context.loc.series_content_type;
    }
  }
}
