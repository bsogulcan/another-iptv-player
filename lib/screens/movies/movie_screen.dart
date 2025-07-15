import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/utils/get_playlist_type.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';

import '../../../widgets/player_widget.dart';

class MovieScreen extends StatefulWidget {
  final ContentItem contentItem;

  const MovieScreen({super.key, required this.contentItem});

  @override
  _MovieScreenState createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PlayerWidget(contentItem: widget.contentItem),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Kanal Başlığı
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.contentItem.name,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (isXtreamCode)
                            ...List.generate(5, (index) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  index <
                                          (widget
                                                  .contentItem
                                                  .vodStream!
                                                  .rating5based
                                                  .round() ??
                                              0)
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  color: Colors.amber,
                                  size: 24,
                                ),
                              );
                            }),
                          const SizedBox(width: 12),
                          if (isXtreamCode)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${widget.contentItem.vodStream!.rating5based.toStringAsFixed(1) ?? '0.0'}/5',
                                style: TextStyle(
                                  color: Colors.amber.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      _buildDetailCard(
                        icon: Icons.calendar_today,
                        title: context.loc.creation_date,
                        value: _formatDate('1746225795'),
                      ),
                      const SizedBox(height: 12),

                      _buildDetailCard(
                        icon: Icons.category,
                        title: context.loc.category_id,
                        value:
                            widget.contentItem.vodStream?.categoryId ??
                            context.loc.not_found_in_category,
                      ),
                      const SizedBox(height: 12),

                      _buildDetailCard(
                        icon: Icons.tag,
                        title: 'Stream ID',
                        value: widget.contentItem.id.toString(),
                      ),
                      const SizedBox(height: 12),

                      _buildDetailCard(
                        icon: Icons.video_file,
                        title: context.loc.format,
                        value:
                            widget.contentItem.containerExtension
                                ?.toUpperCase() ??
                            'Bilinmiyor',
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: Colors.blue),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? timestamp) {
    if (timestamp == null) return 'Bilinmiyor';
    try {
      DateTime date = DateTime.fromMillisecondsSinceEpoch(
        int.parse(timestamp) * 1000,
      );
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      return 'Bilinmiyor';
    }
  }
}
