import 'package:flutter/material.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';

class WatchHistoryDialogs {
  static void showRemoveDialog(
      BuildContext context, {
        required VoidCallback onConfirm,
      }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc.remove_from_history),
        content: Text(
          context.loc.remove_from_history_confirmation,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.loc.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: Text(context.loc.remove, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  static void showClearOldDialog(
      BuildContext context, {
        required VoidCallback onConfirm,
      }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc.clear_old_records),
        content: Text(
          context.loc.clear_old_records_confirmation,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.loc.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: Text(context.loc.clear_old),
          ),
        ],
      ),
    );
  }

  static void showClearAllDialog(
      BuildContext context, {
        required VoidCallback onConfirm,
      }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc.clear_all_history),
        content: Text(
          context.loc.clear_all_history_confirmation,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.loc.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: Text(context.loc.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}