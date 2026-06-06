import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:flutter/material.dart';
import '../../../../models/playlist_model.dart';
import '../../utils/playlist_utils.dart';

class PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _PlaylistIcon(type: playlist.type),
              const SizedBox(width: 16),
              Expanded(child: _PlaylistInfo(playlist: playlist)),
              _PlaylistMenu(onDelete: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistIcon extends StatelessWidget {
  final PlaylistType type;

  const _PlaylistIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: PlaylistUtils.getPlaylistColor(type),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Icon(
        PlaylistUtils.getPlaylistIcon(type),
        color: Colors.white,
        size: 24,
      ),
    );
  }
}

class _PlaylistInfo extends StatelessWidget {
  final Playlist playlist;

  const _PlaylistInfo({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          playlist.name,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _TypeChip(type: playlist.type),
            const SizedBox(width: 8),
            const Icon(Icons.access_time, size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              PlaylistUtils.formatDate(playlist.createdAt),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        if (playlist.url != null) ...[
          const SizedBox(height: 4),
          Text(
            playlist.url!,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final PlaylistType type;

  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final color = PlaylistUtils.getPlaylistColor(type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.toString().split('.').last.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _PlaylistMenu extends StatelessWidget {
  final VoidCallback onDelete;

  const _PlaylistMenu({required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text(context.loc.delete, style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value == 'delete') {
          onDelete();
        }
      },
    );
  }
}
