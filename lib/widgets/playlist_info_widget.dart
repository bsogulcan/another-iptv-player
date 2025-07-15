import 'package:another_iptv_player/utils/get_playlist_type.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'section_title_widget.dart';
import 'info_tile_widget.dart';

class PlaylistInfoWidget extends StatelessWidget {
  final Playlist playlist;

  const PlaylistInfoWidget({super.key, required this.playlist});

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
                value: playlist.name,
              ),
              InfoTileWidget(
                icon: Icons.link,
                label: context.loc.server_url,
                value: playlist.url ?? context.loc.not_found_in_category,
              ),
              if (isXtreamCode)
                InfoTileWidget(
                  icon: Icons.person,
                  label: context.loc.username,
                  value: playlist.username ?? context.loc.not_found_in_category,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
