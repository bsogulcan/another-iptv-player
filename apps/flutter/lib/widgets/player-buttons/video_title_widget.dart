import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/playlist_content_model.dart';
import '../../../services/event_bus.dart';
import '../../../services/player_state.dart';

class VideoTitleWidget extends StatefulWidget {
  const VideoTitleWidget({super.key});

  @override
  State<VideoTitleWidget> createState() => _VideoTitleWidgetState();
}

class _VideoTitleWidgetState extends State<VideoTitleWidget> {
  late StreamSubscription subscription;
  String videoTitle = PlayerState.currentContent?.name ?? PlayerState.title;

  @override
  void initState() {
    super.initState();
    
    if (PlayerState.currentContent != null) {
      videoTitle = PlayerState.currentContent!.name;
    } else if (PlayerState.title.isNotEmpty) {
      videoTitle = PlayerState.title;
    }
    
    subscription = EventBus().on<ContentItem>('player_content_item').listen((
      ContentItem data,
    ) {
      if (mounted) {
        setState(() {
          videoTitle = data.name;
        });
      }
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentContent = PlayerState.currentContent;
    final currentTitle = currentContent?.name ?? PlayerState.title;
    if (currentTitle.isNotEmpty && currentTitle != videoTitle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            videoTitle = currentTitle;
          });
        }
      });
    }
    
    return Text(
      videoTitle,
      style: const TextStyle(
        color: Colors.white,
      ),
      maxLines: 1,
      overflow: TextOverflow.clip,
    );
  }
}
