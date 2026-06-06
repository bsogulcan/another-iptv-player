import 'package:another_iptv_player/utils/get_playlist_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'section_title_widget.dart';
import 'info_tile_widget.dart';

class PlaylistInfoWidget extends StatefulWidget {
  final Playlist playlist;

  const PlaylistInfoWidget({super.key, required this.playlist});

  @override
  State<PlaylistInfoWidget> createState() => _PlaylistInfoWidgetState();
}

class _PlaylistInfoWidgetState extends State<PlaylistInfoWidget> {
  bool _passwordVisible = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitleWidget(title: context.loc.playlist_information),
        Card(
          child: Column(
            children: [
              InfoTileWidget(
                icon: Icons.label_outline,
                label: context.loc.playlist_name,
                value: widget.playlist.name,
                copyOnTap: true,
              ),
              const Divider(height: 1),
              InfoTileWidget(
                icon: Icons.link,
                label: context.loc.server_url,
                value: widget.playlist.url ?? context.loc.not_found_in_category,
                copyOnTap: true,
              ),
              if (isXtreamCode) ...[
                const Divider(height: 1),
                InfoTileWidget(
                  icon: Icons.person,
                  label: context.loc.username,
                  value: widget.playlist.username ?? context.loc.not_found_in_category,
                  copyOnTap: true,
                ),
              ],
              if (isXtreamCode && widget.playlist.password != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.lock_outline, color: Colors.grey[700]),
                  title: Text(context.loc.password, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    _passwordVisible
                        ? widget.playlist.password!
                        : '•' * (widget.playlist.password!.length),
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  dense: true,
                  trailing: IconButton(
                    icon: Icon(
                      _passwordVisible ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _passwordVisible = !_passwordVisible;
                      });
                    },
                  ),
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: widget.playlist.password!),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.loc.copied_to_clipboard),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
