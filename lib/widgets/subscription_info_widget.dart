import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/api_response.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/utils/subscription_utils.dart';
import 'info_tile_widget.dart';
import 'section_title_widget.dart';

class SubscriptionInfoWidget extends StatelessWidget {
  final ApiResponse? serverInfo;

  const SubscriptionInfoWidget({super.key, required this.serverInfo});


  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitleWidget(title: context.loc.subscription_details),
        Card(
          child: Column(
            children: [
              InfoTileWidget(
                icon: Icons.schedule,
                label: context.loc.remaining_day_title,
                value: SubscriptionUtils.getRemainingDays(serverInfo, context),
                valueColor: SubscriptionUtils.getStatusColor(serverInfo, context),
              ),
              if (serverInfo?.userInfo != null)
                InfoTileWidget(
                  icon: Icons.devices,
                  label: context.loc.active_connection,
                  value: serverInfo!.userInfo.activeCons.toString(),
                ),
              if (serverInfo?.userInfo != null)
                InfoTileWidget(
                  icon: Icons.device_hub,
                  label: context.loc.maximum_connection,
                  value: serverInfo!.userInfo.maxConnections.toString(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
