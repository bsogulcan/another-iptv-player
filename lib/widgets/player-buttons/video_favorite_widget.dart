import 'dart:async';
import 'package:another_iptv_player/controllers/favorites_controller.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/event_bus.dart';
import 'package:another_iptv_player/services/player_state.dart';
import 'package:flutter/material.dart';
import '../../models/content_type.dart';

class VideoFavoriteWidget extends StatefulWidget {
  const VideoFavoriteWidget({super.key});

  @override
  State<VideoFavoriteWidget> createState() => _VideoFavoriteWidgetState();
}

class _VideoFavoriteWidgetState extends State<VideoFavoriteWidget> {
  bool _isFavorite = false;
  late FavoritesController _favoritesController;
  StreamSubscription? _contentItemSubscription;

  @override
  void initState() {
    super.initState();
    _favoritesController = FavoritesController();
    _checkFavoriteStatus();

    // ContentItem değiştiğinde favori durumunu güncelle
    _contentItemSubscription = EventBus()
        .on<ContentItem>('player_content_item')
        .listen((ContentItem item) {
      _checkFavoriteStatus();
    });
  }

  @override
  void dispose() {
    _contentItemSubscription?.cancel();
    _favoritesController.dispose();
    super.dispose();
  }

  Future<void> _checkFavoriteStatus() async {
    final currentContent = PlayerState.currentContent;
    if (currentContent == null) return;

    if (currentContent.contentType == ContentType.liveStream ||
        currentContent.contentType == ContentType.vod) {
      final isFavorite = await _favoritesController.isFavorite(
        currentContent.id,
        currentContent.contentType,
      );
      if (mounted) {
        setState(() {
          _isFavorite = isFavorite;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isFavorite = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final currentContent = PlayerState.currentContent;
    if (currentContent == null) return;

    if (currentContent.contentType == ContentType.liveStream ||
        currentContent.contentType == ContentType.vod) {
      final result = await _favoritesController.toggleFavorite(currentContent);
      if (mounted) {
        setState(() {
          _isFavorite = result;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentContent = PlayerState.currentContent;
    
    // Sadece canlı yayın ve filmler için göster
    if (currentContent == null ||
        (currentContent.contentType != ContentType.liveStream &&
            currentContent.contentType != ContentType.vod)) {
      return const SizedBox.shrink();
    }

    return IconButton(
      tooltip: _isFavorite ? 'Favorilerden Kaldır' : 'Favorilere Ekle',
      icon: Icon(
        _isFavorite ? Icons.favorite : Icons.favorite_border,
        color: _isFavorite ? Colors.red : Colors.white,
      ),
      onPressed: _toggleFavorite,
    );
  }
}

