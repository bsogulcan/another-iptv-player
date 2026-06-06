import 'package:flutter/material.dart';

Widget buildFullScreenLoadingWidget() {
  return const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Yükleniyor...'),
      ],
    ),
  );
}