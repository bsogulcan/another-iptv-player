import 'package:flutter/material.dart';
import '../../l10n/localization_extension.dart';
import '../../models/playlist_content_model.dart';
import '../../widgets/player_widget.dart';
import '../../controllers/favorites_controller.dart';

class M3uPlayerScreen extends StatefulWidget {
  final ContentItem contentItem;

  const M3uPlayerScreen({super.key, required this.contentItem});

  @override
  State<M3uPlayerScreen> createState() => _M3uPlayerScreenState();
}

class _M3uPlayerScreenState extends State<M3uPlayerScreen> {
  late FavoritesController _favoritesController;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _favoritesController = FavoritesController();
    _checkFavoriteStatus();
  }

  @override
  void dispose() {
    _favoritesController.dispose();
    super.dispose();
  }

  Future<void> _checkFavoriteStatus() async {
    final isFavorite = await _favoritesController.isFavorite(
      widget.contentItem.id,
      widget.contentItem.contentType,
    );
    if (mounted) {
      setState(() {
        _isFavorite = isFavorite;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final result = await _favoritesController.toggleFavorite(widget.contentItem);
    if (mounted) {
      setState(() {
        _isFavorite = result;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result ? context.loc.added_to_favorites : context.loc.removed_from_favorites,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PlayerWidget(contentItem: widget.contentItem),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 5, 0, 0),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.contentItem.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _toggleFavorite,
                                    icon: Icon(
                                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                                      color: _isFavorite ? Colors.red : Colors.grey,
                                      size: 28,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
