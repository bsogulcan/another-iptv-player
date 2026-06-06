import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/utils/responsive_helper.dart';

import '../content_card.dart';

class ContentGrid extends StatelessWidget {
  final List<ContentItem> items;
  final Function(ContentItem) onItemTap;

  const ContentGrid({
    super.key,
    required this.items,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: ResponsiveHelper.getCrossAxisCount(context),
        childAspectRatio: 0.65,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => ContentCard(
        content: items[index],
        width: 150,
        onTap: () => onItemTap(items[index]),
      ),
    );
  }
}