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

  static const double _desktopBreakpoint = 900.0;
  static const double _largeScreenBreakpoint = 1200.0;
  static const double _defaultNavWidth = 80.0;
  static const double _largeNavWidth = 100.0;
  static const double _defaultItemHeight = 60.0;
  static const double _largeItemHeight = 70.0;
  static const double _defaultIconSize = 24.0;
  static const double _largeIconSize = 28.0;
  static const double _defaultFontSize = 10.0;
  static const double _largeFontSize = 11.0;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _desktopBreakpoint) {
          return _buildDesktopLayout(context, controller, constraints);
        }

        return _buildMobileLayout(context, controller);
      },
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

  Widget _buildMobileLayout(
    BuildContext context,
    XtreamCodeHomeController controller,
  ) {
    return Scaffold(
      body: _buildPageView(controller),
      bottomNavigationBar: _buildBottomNavigationBar(context, controller),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    XtreamCodeHomeController controller,
    BoxConstraints constraints,
  ) {
    return Scaffold(
      body: Row(
        children: [
          _buildDesktopNavigationBar(context, controller, constraints),
          Expanded(
            child: _buildPageView(controller),
          ),
        ],
      ),
    );
  }

  Widget _buildPageView(XtreamCodeHomeController controller) {
    return IndexedStack(
      index: controller.currentIndex,
      children: _buildPages(controller),
    );
  }

  List<Widget> _buildPages(XtreamCodeHomeController controller) {
    return [
      WatchHistoryScreen(
        key: ValueKey('watch_history_${controller.currentIndex}'),
        playlistId: widget.playlist.id,
      ),
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
    if (ResponsiveHelper.isDesktopOrTV(context)) {
      return _buildDesktopSliverAppBar(context, contentType);
    }

    return _buildMobileSliverAppBar(context, controller, contentType);
  }

  SliverAppBar _buildDesktopSliverAppBar(
    BuildContext context,
    ContentType contentType,
  ) {
    return SliverAppBar(
      title: const SizedBox.shrink(),
      floating: true,
      snap: true,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => _navigateToSearch(context, contentType),
        ),
      ],
    );
  }

  SliverAppBar _buildMobileSliverAppBar(
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
          onPressed: () => _navigateToSearch(context, contentType),
        ),
      ],
    );
  }

  void _navigateToSearch(BuildContext context, ContentType contentType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchScreen(contentType: contentType),
      ),
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
    return _getNavigationItems(context).map((item) {
      return BottomNavigationBarItem(
        icon: Icon(item.icon),
        label: item.label,
      );
    }).toList();
  }

  Widget _buildDesktopNavigationBar(
    BuildContext context,
    XtreamCodeHomeController controller,
    BoxConstraints constraints,
  ) {
    final navWidth = _getNavigationWidth(constraints.maxWidth);
    
    return Container(
      width: navWidth,
      decoration: _getNavigationBarDecoration(context),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildDesktopNavigationItems(context, controller, constraints),
        ],
      ),
    );
  }

  Widget _buildDesktopNavigationItems(
    BuildContext context,
    XtreamCodeHomeController controller,
    BoxConstraints constraints,
  ) {
    final items = _getNavigationItems(context);
    final sizes = _getNavigationSizes(constraints.maxWidth);

    return Column(
      children: items.map((item) {
        final isSelected = controller.currentIndex == item.index;
        return _buildNavigationItem(
          context,
          item,
          isSelected,
          sizes,
          () => controller.onNavigationTap(item.index),
        );
      }).toList(),
    );
  }

  Widget _buildNavigationItem(
    BuildContext context,
    NavigationItem item,
    bool isSelected,
    NavigationSizes sizes,
    VoidCallback onTap,
  ) {
    return Container(
      width: double.infinity,
      height: sizes.itemHeight,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected 
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              color: _getIconColor(context, isSelected),
              size: sizes.iconSize,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                color: _getTextColor(context, isSelected),
                fontSize: sizes.fontSize,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _getNavigationBarDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        right: BorderSide(
          color: Theme.of(context).dividerColor,
          width: 0.5,
        ),
      ),
    );
  }

  double _getNavigationWidth(double screenWidth) {
    return screenWidth >= _largeScreenBreakpoint ? _largeNavWidth : _defaultNavWidth;
  }

  NavigationSizes _getNavigationSizes(double screenWidth) {
    final isLargeScreen = screenWidth >= _largeScreenBreakpoint;
    
    return NavigationSizes(
      itemHeight: isLargeScreen ? _largeItemHeight : _defaultItemHeight,
      iconSize: isLargeScreen ? _largeIconSize : _defaultIconSize,
      fontSize: isLargeScreen ? _largeFontSize : _defaultFontSize,
    );
  }

  Color _getIconColor(BuildContext context, bool isSelected) {
    return isSelected 
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
  }

  Color _getTextColor(BuildContext context, bool isSelected) {
    return isSelected 
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
  }

  List<NavigationItem> _getNavigationItems(BuildContext context) {
    return [
      NavigationItem(
        icon: Icons.history,
        label: context.loc.history,
        index: 0,
      ),
      NavigationItem(
        icon: Icons.live_tv,
        label: context.loc.live,
        index: 1,
      ),
      NavigationItem(
        icon: Icons.movie_outlined,
        label: context.loc.movie,
        index: 2,
      ),
      NavigationItem(
        icon: Icons.tv,
        label: context.loc.series_plural,
        index: 3,
      ),
      NavigationItem(
        icon: Icons.settings,
        label: context.loc.settings,
        index: 4,
      ),
    ];
  }
}

class NavigationItem {
  final IconData icon;
  final String label;
  final int index;

  const NavigationItem({
    required this.icon,
    required this.label,
    required this.index,
  });
}

class NavigationSizes {
  final double itemHeight;
  final double iconSize;
  final double fontSize;

  const NavigationSizes({
    required this.itemHeight,
    required this.iconSize,
    required this.fontSize,
  });
}
