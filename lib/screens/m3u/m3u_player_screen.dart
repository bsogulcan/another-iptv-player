import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/playlist_content_model.dart';
import '../../widgets/player_widget.dart';

class M3uPlayerScreen extends StatefulWidget {
  final ContentItem contentItem;

  const M3uPlayerScreen({super.key, required this.contentItem});

  @override
  State<M3uPlayerScreen> createState() => _M3uPlayerScreenState();
}

class _M3uPlayerScreenState extends State<M3uPlayerScreen> {
  @override
  void initState() {
    super.initState();
    _hideSystemUI();
  }

  @override
  void dispose() {
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SizedBox.expand(
          child: PlayerWidget(contentItem: widget.contentItem),
        ),
      ),
    );
  }
}
