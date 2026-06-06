import 'package:flutter/material.dart';

class ResponsiveHelper {
  static double getCardWidth(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth >= 1200) {
      return 160;
    } else if (screenWidth >= 600) {
      return 130;
    } else {
      return 110;
    }
  }

  static double getCardHeight(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth >= 1200) {
      return 220;
    } else if (screenWidth >= 600) {
      return 190;
    } else {
      return 160;
    }
  }

  static int getCrossAxisCount(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth >= 1200) {
      return 6;
    } else if (screenWidth >= 900) {
      return 5;
    } else if (screenWidth >= 600) {
      return 4;
    } else if (screenWidth >= 400) {
      return 3;
    } else {
      return 2;
    }
  }

  static bool isDesktopOrTV(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    return screenWidth >= 900;
  }
}
