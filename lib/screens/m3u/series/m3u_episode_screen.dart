import 'dart:async';
import 'package:another_iptv_player/models/m3u_series.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/watch_history.dart';
import '../../../models/content_type.dart';
import '../../../services/event_bus.dart';
import '../../../widgets/loading_widget.dart';
import '../../../widgets/player_widget.dart';

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

  @override
  void initState() {
    super.initState();
    contentItem = widget.contentItem;
    _hideSystemUI();
    _initializeQueue();
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

  Future<void> _initializeQueue() async {
    // Tüm sezonların tüm bölümlerini ekle (sadece mevcut sezonu değil)
    allContents = widget.episodes
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
  Widget build(BuildContext context) {
    if (!allContentsLoaded) {
      return buildFullScreenLoadingWidget();
    } else {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: SizedBox.expand(
            child: PlayerWidget(contentItem: widget.contentItem, queue: allContents),
          ),
        ),
      );
    }
  }

}
