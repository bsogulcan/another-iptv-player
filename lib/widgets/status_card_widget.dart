import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/api_response.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/utils/subscription_utils.dart';

class StatusCardWidget extends StatelessWidget {
  final ApiResponse? serverInfo;

  const StatusCardWidget({super.key, required this.serverInfo});

  String _getServerStatus(BuildContext context) {
    return serverInfo != null
        ? context.loc.connected
        : context.loc.no_connection;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          SubscriptionUtils.getStatusColor(serverInfo, context) == Colors.green
              ? Icons.check_circle
              : SubscriptionUtils.getStatusColor(serverInfo, context) == Colors.orange
              ? Icons.warning
              : Icons.error,
          color: SubscriptionUtils.getStatusColor(serverInfo, context),
          size: 36,
        ),
        title: Text(
          _getServerStatus(context),
          style: TextStyle(color: SubscriptionUtils.getStatusColor(serverInfo, context)),
        ),
        subtitle: Text(
          context.loc.subscription_remaining_day(SubscriptionUtils.getRemainingDays(serverInfo, context)),
        ),
      ),
    );
  }
}
