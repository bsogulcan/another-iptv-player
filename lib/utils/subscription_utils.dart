import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/api_response.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';

class SubscriptionUtils {
  /// Calculates the remaining days for a subscription
  /// 
  /// [serverInfo] - The API response containing user information
  /// [context] - BuildContext for localization
  /// 
  /// Returns a localized string with remaining days or status
  static String getRemainingDays(
    ApiResponse? serverInfo,
    BuildContext context,
  ) {
    if (serverInfo?.userInfo.expDate != null) {
      final expDate = serverInfo!.userInfo.expDate;
      try {
        final expiryDate = DateTime.fromMillisecondsSinceEpoch(
          int.parse(expDate.toString()) * 1000,
        );
        final now = DateTime.now();
        final difference = expiryDate.difference(now).inDays + 1;
        return difference > 0
            ? context.loc.remaining_day(difference.toString())
            : context.loc.expired;
      } catch (e) {
        return context.loc.not_found_in_category;
      }
    }
    return context.loc.not_found_in_category;
  }

  /// Gets the status color based on remaining days
  /// 
  /// [serverInfo] - The API response containing user information
  /// [context] - BuildContext for localization
  /// 
  /// Returns a color indicating the subscription status
  static Color getStatusColor(
    ApiResponse? serverInfo,
    BuildContext context,
  ) {
    if (serverInfo != null) {
      final remaining = getRemainingDays(serverInfo, context);
      if (remaining == context.loc.expired) return Colors.red;
      if (remaining.contains(context.loc.day)) {
        final RegExp numberRegex = RegExp(r'\d+');
        final match = numberRegex.firstMatch(remaining);
        if (match != null) {
          final days = int.tryParse(match.group(0)!) ?? 0;
          if (days <= 7) return Colors.orange;
          return Colors.green;
        }
      }
    }
    return Colors.grey;
  }
}
