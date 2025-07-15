import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/screens/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:another_iptv_player/controllers/xtream_code_home_controller.dart';
import 'package:another_iptv_player/models/api_configuration_model.dart';
import 'package:another_iptv_player/models/category_view_model.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';
import 'package:another_iptv_player/screens/category_detail_screen.dart';
import 'package:another_iptv_player/screens/xtream-codes/xtream_code_playlist_settings_screen.dart';
import 'package:another_iptv_player/screens/watch_history_screen.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/utils/navigate_by_content_type.dart';
import 'package:another_iptv_player/utils/responsive_helper.dart';
import 'package:another_iptv_player/widgets/category_section.dart';
import '../../models/content_type.dart';

class XtreamCodeHomeScreen extends StatefulWidget {
  final Playlist playlist;

  const XtreamCodeHomeScreen({super.key, required this.playlist});

  @override
  State<XtreamCodeHomeScreen> createState() => _XtreamCodeHomeScreenState();
}

class _XtreamCodeHomeScreenState extends State<XtreamCodeHomeScreen> {
  late XtreamCodeHomeController _controller;

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
    final repository = IptvRepository(
      ApiConfig(
        baseUrl: widget.playlist.url!,
        username: widget.playlist.username!,
        password: widget.playlist.password!,
      ),
      widget.playlist.id,
    );

    AppState.xtreamCodeRepository = repository;
    _controller = XtreamCodeHomeController();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<XtreamCodeHomeController>(
        builder: (context, controller, child) =>
            _buildMainContent(context, controller),
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    XtreamCodeHomeController controller,
  ) {
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
            Text(context.loc.loading_playlists),
          ],
        ),
      ),
    );
  }

  Widget _buildPageView(XtreamCodeHomeController controller) {
    return PageView(
      controller: controller.pageController,
      onPageChanged: controller.onPageChanged,
      children: _buildPages(controller),
    );
  }

  List<Widget> _buildPages(XtreamCodeHomeController controller) {
    return [
      WatchHistoryScreen(playlistId: widget.playlist.id),
      _buildContentPage(
        controller.liveCategories!,
        ContentType.liveStream,
        controller,
      ),
      _buildContentPage(
        controller.movieCategories!,
        ContentType.vod,
        controller,
      ),
      _buildContentPage(
        controller.seriesCategories!,
        ContentType.series,
        controller,
      ),
      XtreamCodePlaylistSettingsScreen(playlist: widget.playlist),
    ];
  }

  Widget _buildContentPage(
    List<CategoryViewModel> categories,
    ContentType contentType,
    XtreamCodeHomeController controller,
  ) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        _buildSliverAppBar(context, controller, contentType),
      ],
      body: _buildCategoryList(categories, contentType),
    );
  }

  SliverAppBar _buildSliverAppBar(
    BuildContext context,
    XtreamCodeHomeController controller,
    ContentType contentType,
  ) {
    return SliverAppBar(
      title: SelectableText(
        controller.getPageTitle(context),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      floating: true,
      snap: true,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SearchScreen(contentType: contentType),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryList(
    List<CategoryViewModel> categories,
    ContentType contentType,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: categories.length,
      itemBuilder: (context, index) =>
          _buildCategorySection(categories[index], contentType),
    );
  }

  Widget _buildCategorySection(
    CategoryViewModel category,
    ContentType contentType,
  ) {
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
    XtreamCodeHomeController controller,
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
