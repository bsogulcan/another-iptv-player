import 'package:flutter/material.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';

class ColorPickerTileWidget extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final ValueChanged<Color> onChanged;

  const ColorPickerTileWidget({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, size: 20),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      trailing: GestureDetector(
        onTap: () => _showColorPickerDialog(context),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  void _showColorPickerDialog(BuildContext context) {
    final colors = [
      Colors.white,
      Colors.black,
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.yellow,
      Colors.orange,
      Colors.purple,
      const Color(0xffffffff),
      const Color(0xaa000000),
      const Color(0x80000000),
      const Color(0x40000000),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.loc.pick_color),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors
              .map(
                (c) => GestureDetector(
                  onTap: () {
                    onChanged(c);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: color == c
                            ? Theme.of(context).primaryColor
                            : Colors.grey,
                        width: color == c ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.loc.cancel),
          ),
        ],
      ),
    );
  }
}
