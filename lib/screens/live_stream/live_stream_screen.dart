import 'dart:async';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/utils/get_playlist_type.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import '../../../models/content_type.dart';
import '../../../services/event_bus.dart';
import '../../../utils/responsive_helper.dart';
import '../../../widgets/content_item_card_widget.dart';
import '../../../widgets/loading_widget.dart';
import '../../../widgets/player_widget.dart';

class LiveStreamScreen extends StatefulWidget {
  final ContentItem content;

  const LiveStreamScreen({super.key, required this.content});

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  late ContentItem contentItem;
  List<ContentItem> allContents = [];
  bool allContentsLoaded = false;
  int selectedContentItemIndex = 0;
  late StreamSubscription contentItemIndexChangedSubscription;

  @override
  void initState() {
    super.initState();
    contentItem = widget.content;
    _initializeQueue();
  }

  Future<void> _initializeQueue() async {
    allContents = isXtreamCode
        ? (await AppState.xtreamCodeRepository!.getLiveChannelsByCategoryId(
            categoryId: widget.content.liveStream!.categoryId,
          ))!.map((x) {
            return ContentItem(
              x.streamId,
              x.name,
              x.streamIcon,
              ContentType.liveStream,
              liveStream: x,
            );
          }).toList()
        : (await AppState.m3uRepository!.getM3uItemsByCategoryId(
            categoryId: widget.content.m3uItem!.categoryId!,
          ))!.map((x) {
            return ContentItem(
              x.url,
              x.name ?? 'NO NAME',
              x.tvgLogo ?? '',
              ContentType.liveStream,
              m3uItem: x,
            );
          }).toList();

    setState(() {
      selectedContentItemIndex = allContents.indexWhere(
        (element) => element.id == widget.content.id,
      );
      allContentsLoaded = true;
    });

    contentItemIndexChangedSubscription = EventBus()
        .on<int>('player_content_item_index')
        .listen((int index) {
          if (!mounted) return;

          setState(() {
            selectedContentItemIndex = index;
            contentItem = allContents[selectedContentItemIndex];
          });
        });
  }

  @override
  void dispose() {
    contentItemIndexChangedSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!allContentsLoaded) {
      return Scaffold(body: SafeArea(child: buildFullScreenLoadingWidget()));
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PlayerWidget(contentItem: widget.content, queue: allContents),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SelectableText(
                                  context.loc.live.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SelectableText(
                              contentItem.name,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SelectableText(
                        context.loc.other_channels,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      ContentItemCardWidget(
                        cardHeight: ResponsiveHelper.getCardHeight(context),
                        cardWidth: ResponsiveHelper.getCardWidth(context),
                        contentItems: allContents,
                        onContentTap: _onContentTap,
                        initialSelectedIndex: selectedContentItemIndex,
                        isSelectionModeEnabled: true,
                      ),
                      const SizedBox(height: 24),

                      // Kanal Bilgileri
                      SelectableText(
                        context.loc.channel_information,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      _buildInfoCard(
                        icon: Icons.tv,
                        title: context.loc.channel_id,
                        value: contentItem.id.toString(),
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 12),

                      _buildInfoCard(
                        icon: Icons.category,
                        title: context.loc.category_id,
                        value:
                            contentItem.liveStream?.categoryId ??
                            context.loc.not_found_in_category,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 12),

                      _buildInfoCard(
                        icon: Icons.high_quality,
                        title: context.loc.quality,
                        value: _getQualityText(),
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 12),

                      _buildInfoCard(
                        icon: Icons.signal_cellular_alt,
                        title: context.loc.stream_type,
                        value:
                            contentItem.containerExtension?.toUpperCase() ??
                            context.loc.live,
                        color: Colors.purple,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getQualityText() {
    // Bu fonksiyon content modeline göre kalite bilgisini döndürebilir
    // Şu an için sabit bir değer döndürüyorum
    return 'HD';
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
}
