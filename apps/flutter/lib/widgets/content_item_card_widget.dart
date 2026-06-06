import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/playlist_content_model.dart';
import '../../services/event_bus.dart';
import '../../utils/helpers.dart';
import 'content_card.dart';

class ContentItemCardWidget extends StatefulWidget {
  final double cardWidth;
  final double cardHeight;
  final Function(ContentItem)? onContentTap;
  final List<ContentItem> contentItems;
  int initialSelectedIndex;
  final bool isSelectionModeEnabled;

  ContentItemCardWidget({
    super.key,
    required this.cardHeight,
    required this.cardWidth,
    required this.contentItems,
    this.onContentTap,
    this.initialSelectedIndex = -1,
    this.isSelectionModeEnabled = false,
  });

  @override
  State<ContentItemCardWidget> createState() => _ContentItemCardWidgetState();
}

class _ContentItemCardWidgetState extends State<ContentItemCardWidget> {
  late StreamSubscription contentItemIndexChangedSubscription;
  late StreamSubscription contentItemIndexSubscription;
  int selectedIndex = -1;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    selectedIndex = widget.initialSelectedIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialSelectedIndex >= 0) {
        _scrollToIndex(widget.initialSelectedIndex);
      }
    });

    contentItemIndexSubscription = EventBus()
        .on<int>('player_content_item_index')
        .listen((int index) {
          if (!mounted) return;
          selectAndScrollToIndex(index);
        });

    contentItemIndexChangedSubscription = EventBus()
        .on<int>('player_content_item_index_changed')
        .listen((int index) {
          if (!mounted) return;
          selectAndScrollToIndex(index);
        });
  }

  @override
  void dispose() {
    contentItemIndexSubscription.cancel();
    contentItemIndexChangedSubscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) {
    if (index < 0 || index >= widget.contentItems.length) return;

    if (!_scrollController.hasClients) return;

    double screenWidth = MediaQuery.of(context).size.width;

    double cardTotalWidth = widget.cardWidth + 8;
    double targetPosition = (cardTotalWidth * index) + (widget.cardWidth / 2) - (screenWidth / 2);

    double maxScrollExtent = _scrollController.position.maxScrollExtent;
    double minScrollExtent = _scrollController.position.minScrollExtent;

    if (targetPosition < minScrollExtent) {
      targetPosition = minScrollExtent;
    } else if (targetPosition > maxScrollExtent) {
      targetPosition = maxScrollExtent;
    }

    _scrollController.animateTo(
      targetPosition,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void selectAndScrollToIndex(int index) {
    if (index < 0 || index >= widget.contentItems.length || !widget.isSelectionModeEnabled) return;

    setState(() {
      selectedIndex = index;
    });

    // _scrollToIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.cardHeight,
      child: isDesktop
          ? Scrollbar(
              controller: _scrollController,
              thumbVisibility: false,
              trackVisibility: false,
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 12),
                itemCount: widget.contentItems.length,
                itemBuilder: (context, index) {
                  return Container(
                    width: widget.cardWidth,
                    margin: EdgeInsets.symmetric(horizontal: 4),
                    child: ContentCard(
                      content: widget.contentItems[index],
                      width: widget.cardWidth,
                      onTap: () {
                        selectAndScrollToIndex(index);
                        widget.onContentTap?.call(widget.contentItems[index]);
                      },
                      isSelected: selectedIndex == index,
                      key: widget.key,
                    ),
                  );
                },
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 12),
              itemCount: widget.contentItems.length,
              itemBuilder: (context, index) {
                return Container(
                  width: widget.cardWidth,
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  child: ContentCard(
                    content: widget.contentItems[index],
                    width: widget.cardWidth,
                    onTap: () {
                      selectAndScrollToIndex(index);
                      widget.onContentTap?.call(widget.contentItems[index]);
                    },
                    isSelected: selectedIndex == index,
                    key: widget.key,

                  ),
                );
              },
            ),
    );
  }
}
