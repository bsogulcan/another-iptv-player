import 'package:flutter/material.dart';

class M3uHomeScreen extends StatefulWidget {
  const M3uHomeScreen({super.key});

  @override
  State<M3uHomeScreen> createState() => _M3uHomeScreenState();
}

class _M3uHomeScreenState extends State<M3uHomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('M3U Playlist Home Page')));
  }
}
