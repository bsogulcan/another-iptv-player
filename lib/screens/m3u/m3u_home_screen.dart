import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/screens/m3u/m3u_items_screen.dart';
import 'package:another_iptv_player/screens/m3u/m3u_playlist_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:another_iptv_player/controllers/m3u_home_controller.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/models/category_view_model.dart';
import 'package:another_iptv_player/repositories/m3u_repository.dart';
import 'package:another_iptv_player/screens/category_detail_screen.dart';
import 'package:another_iptv_player/widgets/category_section.dart';
import 'package:another_iptv_player/utils/responsive_helper.dart';
import 'package:another_iptv_player/utils/navigate_by_content_type.dart';

import '../../services/app_state.dart';
import '../watch_history_screen.dart';

class M3UHomeScreen extends StatefulWidget {
  final Playlist playlist;

  const M3UHomeScreen({super.key, required this.playlist});

  @override
  State<M3UHomeScreen> createState() => _M3UHomeScreenState();
}

class _M3UHomeScreenState extends State<M3UHomeScreen> {
  late M3UHomeController _controller;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _initializeController() {
    AppState.m3uRepository = M3uRepository();
    _controller = M3UHomeController();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<M3UHomeController>(
        builder: (context, controller, child) =>
            _buildMainContent(context, controller),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, M3UHomeController controller) {
    if (controller.isLoading) {
      return _buildLoadingScreen(context);
    }

    return Scaffold(
      body: _buildPageView(controller),
      bottomNavigationBar: _buildBottomNavigationBar(context, controller),
    );
  }

  Widget _buildLoadingScreen(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(context.loc.loading_lists),
          ],
        ),
      ),
    );
  }

  Widget _buildPageView(M3UHomeController controller) {
    return PageView(
      controller: controller.pageController,
      onPageChanged: controller.onPageChanged,
      children: _buildPages(controller),
    );
  }

  List<Widget> _buildPages(M3UHomeController controller) {
    return [
      WatchHistoryScreen(playlistId: widget.playlist.id),
      M3uItemsScreen(m3uItems: controller.m3uItems!),
      _buildContentPage(controller.liveCategories!, controller),
      _buildContentPage(controller.vodCategories!, controller),
      _buildContentPage(controller.seriesCategories!, controller),
      M3uPlaylistSettingsScreen(playlist: widget.playlist),
    ];
  }

  Widget _buildContentPage(
    List<CategoryViewModel> categories,
    M3UHomeController controller,
  ) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        _buildSliverAppBar(context, controller),
      ],
      body: _buildCategoryList(categories),
    );
  }

  SliverAppBar _buildSliverAppBar(
    BuildContext context,
    M3UHomeController controller,
  ) {
    return SliverAppBar(
      title: SelectableText(
        controller.getPageTitle(context),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      floating: true,
      snap: true,
      elevation: 0,
      actions: [],
    );
  }

  Widget _buildCategoryList(List<CategoryViewModel> categories) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: categories.length,
      itemBuilder: (context, index) => _buildCategorySection(categories[index]),
    );
  }

  Widget _buildCategorySection(CategoryViewModel category) {
    return CategorySection(
      category: category,
      cardWidth: ResponsiveHelper.getCardWidth(context),
      cardHeight: ResponsiveHelper.getCardHeight(context),
      onSeeAllTap: () => _navigateToCategoryDetail(category),
      onContentTap: (content) => navigateByContentType(context, content),
    );
  }

  void _navigateToCategoryDetail(CategoryViewModel category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryDetailScreen(category: category),
      ),
    );
  }

  BottomNavigationBar _buildBottomNavigationBar(
    BuildContext context,
    M3UHomeController controller,
  ) {
    return BottomNavigationBar(
      currentIndex: controller.currentIndex,
      onTap: controller.onNavigationTap,
      type: BottomNavigationBarType.fixed,
      items: _buildBottomNavigationItems(context),
    );
  }

  List<BottomNavigationBarItem> _buildBottomNavigationItems(
    BuildContext context,
  ) {
    return [
      BottomNavigationBarItem(
        icon: Icon(Icons.history),
        label: context.loc.history,
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.all_inbox),
        label: context.loc.all,
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.live_tv),
        label: context.loc.live,
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.movie_outlined),
        label: context.loc.movie,
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.tv),
        label: context.loc.series_plural,
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.settings),
        label: context.loc.settings,
      ),
    ];
  }
}
