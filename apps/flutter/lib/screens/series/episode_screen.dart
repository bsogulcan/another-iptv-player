import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/watch_history.dart';
import '../../../models/content_type.dart';
import '../../../services/event_bus.dart';
import '../../../widgets/loading_widget.dart';
import '../../../widgets/player_widget.dart';

class EpisodeScreen extends StatefulWidget {
  final SeriesInfosData? seriesInfo;
  final List<SeasonsData> seasons;
  final List<EpisodesData> episodes;
  final ContentItem contentItem;
  final WatchHistory? watchHistory;

  const EpisodeScreen({
    super.key,
    required this.seriesInfo,
    required this.seasons,
    required this.episodes,
    required this.contentItem,
    this.watchHistory,
  });

  @override
  State<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
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
        x.episodeId,
        x.title,
        x.movieImage ?? "",
        ContentType.series,
        containerExtension: x.containerExtension,
        season: x.season,
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