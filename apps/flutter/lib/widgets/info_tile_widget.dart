import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';

class InfoTileWidget extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool copyOnTap;

  const InfoTileWidget({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.copyOnTap = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[700]),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        value,
        style: TextStyle(color: valueColor),
      ),
      dense: true,
      onTap: copyOnTap
          ? () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.loc.copied_to_clipboard),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          : null,
    );
  }
}