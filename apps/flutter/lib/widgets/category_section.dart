import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/category_view_model.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';

import 'content_item_card_widget.dart';

class CategorySection extends StatelessWidget {
  final CategoryViewModel category;
  final double cardWidth;
  final double cardHeight;
  final VoidCallback? onSeeAllTap;
  final Function(ContentItem)? onContentTap;

  const CategorySection({
    super.key,
    required this.category,
    required this.cardWidth,
    required this.cardHeight,
    this.onSeeAllTap,
    this.onContentTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SelectableText(
                    category.category.categoryName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onSeeAllTap,
                  child: Text(
                    context.loc.see_all,
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          ContentItemCardWidget(
            cardHeight: cardHeight,
            cardWidth: cardWidth,
            onContentTap: onContentTap,
            contentItems: category.contentItems,
            isSelectionModeEnabled: false,
            key: key,
          ),
        ],
      ),
    );
  }
}
