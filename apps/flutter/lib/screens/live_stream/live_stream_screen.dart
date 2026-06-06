import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import '../../../models/content_type.dart';
import '../../../services/event_bus.dart';
import '../../../utils/get_playlist_type.dart';
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
    _hideSystemUI();
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
    _showSystemUI();
    super.dispose();
  }

  void _hideSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  void _showSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!allContentsLoaded) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: buildFullScreenLoadingWidget()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SizedBox.expand(
          child: PlayerWidget(contentItem: widget.content, queue: allContents),
        ),
      ),
    );
  }

}
