import 'dart:async';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/event_bus.dart';
import 'package:another_iptv_player/services/player_state.dart';
import 'package:another_iptv_player/services/playlist_content_state.dart';
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

  // Static metod: Overlay'i dışarıdan kapatmak için
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
  static String? _selectedCategoryId; // Seçili kategori
  static bool _showCategories = false; // Kategoriler mi kanallar mı gösterilecek
  static int? _selectedSeason; // Seçili sezon (diziler için)
  static bool _showSeasons = false; // Sezonlar mı bölümler mi gösterilecek (diziler için)
  static ScrollController? _categoriesScrollController; // Kategoriler scroll controller
  static ScrollController? _channelsScrollController; // Kanallar scroll controller

  // Static metod: Overlay'i dışarıdan kapatmak için
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

    // Context'i güncelle
    _globalContext = context;

    // Event listener'ı sadece bir kez oluştur
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
    // Overlay'i kapatma - başka bir instance hala açık olabilir
    // Overlay sadece kullanıcı kapatırsa veya tüm widget'lar dispose olduğunda kapanmalı
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // M3U playlist ise butonu gösterme
    if (isM3u) {
      return const SizedBox.shrink();
    }

    // Queue yoksa veya tek öğe varsa butonu gösterme
    if (widget.queue == null || widget.queue!.length <= 1) {
      return const SizedBox.shrink();
    }

    // Context'i her build'de güncelle
    _globalContext = context;

    final currentContent = PlayerState.currentContent;
    String tooltip = 'Kanal Seç';
    if (currentContent?.contentType == ContentType.vod) {
      tooltip = 'Filmler';
    } else if (currentContent?.contentType == ContentType.series) {
      tooltip = 'Bölümler';
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
    
    // Canlı yayın ise ve kategori bazlı içerik yüklü değilse yükle
    if (currentContent?.contentType == ContentType.liveStream) {
      if (PlaylistContentState.liveCategories.isEmpty) {
        await PlaylistContentState.loadLiveStreams();
      }
      
      // Mevcut içeriğin kategori ID'sini al
      String? currentCategoryId;
      if (currentContent?.liveStream != null) {
        currentCategoryId = currentContent!.liveStream!.categoryId;
      } else if (currentContent?.m3uItem != null) {
        currentCategoryId = currentContent!.m3uItem!.categoryId;
      }
      
      // Eğer kategori ID bulunduysa ve bu kategori mevcut kategorilerde varsa
      if (currentCategoryId != null && 
          PlaylistContentState.liveCategories.any((c) => c.categoryId == currentCategoryId)) {
        _selectedCategoryId = currentCategoryId;
        _showCategories = false;
      } else {
        // Kategori bulunamadıysa kategorileri göster
        _showCategories = true;
        _selectedCategoryId = null;
      }
      _showSeasons = false;
      _selectedSeason = null;
    } else if (currentContent?.contentType == ContentType.series) {
      // Dizi ise sezon seçimi yap
      final items = widget.queue ?? [];
      if (items.isEmpty) return;
      
      // Mevcut içeriğin sezon numarasını al
      final currentSeason = currentContent?.season;
      
      // Eğer sezon numarası bulunduysa
      if (currentSeason != null) {
        _selectedSeason = currentSeason;
        _showSeasons = false;
      } else {
        // Sezon bulunamadıysa sezonları göster
        _showSeasons = true;
        _selectedSeason = null;
      }
      _showCategories = false;
      _selectedCategoryId = null;
    } else {
      // Diğer içerik tipleri için normal queue kullan
      final items = widget.queue ?? [];
      if (items.isEmpty) return;
      _showCategories = false;
      _showSeasons = false;
      _selectedCategoryId = null;
      _selectedSeason = null;
    }

    // Overlay'i oluşturmadan önce context'i kontrol et
    final overlayContext = _globalContext ?? context;

    // Overlay'i güvenli bir şekilde al
    OverlayState? overlay;
    try {
      overlay = Overlay.of(overlayContext, rootOverlay: true);
    } catch (e) {
      // Overlay bulunamazsa bir sonraki frame'de tekrar dene
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

    // Kanal değiştiğinde overlay'i güncelle
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
    // Context'i null yapma - başka bir widget instance'ı hala kullanıyor olabilir
  }

  Widget _buildOverlay(
    BuildContext context,
    double panelWidth,
  ) {
    // Overlay'in hala açık olduğundan emin ol
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

    // Kategoriler mi kanallar mı gösterilecek
    List<ContentItem> items = [];
    int? selectedIndex; // null olabilir - hiçbir kanal seçili değilse
    
    if (_showCategories && isLiveStream) {
      // Kategoriler gösterilecek - bu durumda items boş, kategoriler ayrı gösterilecek
    } else if (_selectedCategoryId != null && isLiveStream) {
      // Seçili kategorideki kanallar
      items = PlaylistContentState.getLiveStreamsByCategory(_selectedCategoryId!);
      if (currentContent != null) {
        final foundIndex = items.indexWhere(
          (item) => item.id == currentContent.id,
        );
        if (foundIndex != -1) {
          selectedIndex = foundIndex;
        }
        // Eğer mevcut içerik bu kategoride yoksa, selectedIndex null kalır
      }
    } else if (_showSeasons && isSeries) {
      // Sezonlar gösterilecek - bu durumda items boş, sezonlar ayrı gösterilecek
    } else if (_selectedSeason != null && isSeries) {
      // Seçili sezondaki bölümler
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
      // Normal queue kullan (veya sezon seçiliyse o sezonun bölümleri)
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
      // Eğer bulunamazsa widget.currentIndex kullan
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
                // Header
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
                      // Geri butonu (kategori veya sezon seçiliyse)
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
                              // Kategori listesine geri dönüldüğünde scroll'u en üste getir
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
                              ? 'Kategoriler'
                              : _selectedCategoryId != null && isLiveStream
                                  ? PlaylistContentState.liveCategories
                                      .firstWhere((c) => c.categoryId == _selectedCategoryId)
                                      .categoryName
                                      : _showSeasons && isSeries
                                          ? 'Sezonlar'
                                          : _selectedSeason != null && isSeries
                                              ? 'Sezon $_selectedSeason'
                                              : isVod
                                                  ? 'Filmler'
                                                  : isSeries
                                                      ? 'Bölümler'
                                                      : 'Kanal Seç',
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
                // Content
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
    
    // Tüm sezonları al ve sırala
    final seasons = allItems
        .where((item) => item.season != null)
        .map((item) => item.season!)
        .toSet()
        .toList()
      ..sort();
    
    // Mevcut içeriğin sezon numarasını bul
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
                          'Sezon $season',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$episodeCount bölüm',
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
    
    // Mevcut içeriğin kategori ID'sini bul
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
              // Kanal listesine geçildiğinde scroll'u en üste getir
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
                          '$channelCount kanal',
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
          
          // Dizi içeriği için sezonu güncelle
          if (isSeries && item.season != null) {
            if (_selectedSeason != item.season) {
              _selectedSeason = item.season;
              _showSeasons = false;
            }
          }
          
          // Farklı kategoriden kanal seçildiğinde direkt ContentItem gönder
          if (_selectedCategoryId != null && 
              PlayerState.currentContent?.contentType == ContentType.liveStream) {
            // Queue'yu güncelle
            final categoryItems = PlaylistContentState.getLiveStreamsByCategory(_selectedCategoryId!);
            PlayerState.queue = categoryItems;
            PlayerState.currentIndex = index;
            PlayerState.currentContent = item;
            
            // Event gönder
            EventBus().emit('player_content_item_index_changed', index);
            EventBus().emit('player_content_item', item);
          } else {
            // Normal queue kullanılıyorsa - gerçek index'i bul
            final allItems = widget.queue ?? [];
            final realIndex = allItems.indexWhere((queueItem) => queueItem.id == item.id);
            if (realIndex != -1) {
              EventBus().emit('player_content_item_index_changed', realIndex);
            } else {
              EventBus().emit('player_content_item_index_changed', index);
            }
          }
          
          // Sezon değiştiyse overlay'i güncelle
          if (isSeries && item.season != null && _selectedSeason == item.season) {
            _globalOverlayEntry?.markNeedsBuild();
          }
          // Panel kapanmasın
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
              // Thumbnail
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
              // Title and info
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
                            _getContentTypeDisplayName(item.contentType),
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

  String _getContentTypeDisplayName(ContentType contentType) {
    switch (contentType) {
      case ContentType.liveStream:
        return 'Canlı Yayın';
      case ContentType.vod:
        return 'Film';
      case ContentType.series:
        return 'Dizi';
    }
  }
}
