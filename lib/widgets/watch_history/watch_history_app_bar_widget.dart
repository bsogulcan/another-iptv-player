import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:flutter/material.dart';

class WatchHistoryAppBar extends StatelessWidget {
  final VoidCallback? onRefresh;
  final VoidCallback? onClearAll;

  const WatchHistoryAppBar({super.key, this.onRefresh, this.onClearAll});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      title: SelectableText(
        context.loc.history,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      floating: true,
      snap: true,
      elevation: 0,
      actions: [
        PopupMenuButton<String>(
          onSelected: (action) => _handleMenuAction(action, context),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'refresh',
              child: Row(
                children: [
                  Icon(Icons.refresh),
                  SizedBox(width: 8),
                  Text(context.loc.refresh),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'clear_all',
              child: Row(
                children: [
                  Icon(Icons.clear_all, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    context.loc.clear_all,
                    style: TextStyle(color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _handleMenuAction(String action, BuildContext context) {
    switch (action) {
      case 'refresh':
        onRefresh?.call();
        break;
      case 'clear_all':
        _onClearAllTap(context);
        break;
    }
  }

  void _onClearAllTap(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc.clear_all),
        content: Text(context.loc.clear_all_confirmation_message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.loc.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onClearAll?.call();
            },
            child: Text(
              context.loc.delete,
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
