import 'package:another_iptv_player/l10n/localization_extension.dart';
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
            Text(context.loc.loading_lists),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    M3UHomeController controller,
  ) {
    return Scaffold(
      body: _buildPageView(controller),
      bottomNavigationBar: _buildBottomNavigationBar(context, controller),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    M3UHomeController controller,
    BoxConstraints constraints,
  ) {
    return Scaffold(
      body: Row(
        children: [
          _buildDesktopNavigationBar(context, controller, constraints),
          Expanded(child: _buildPageView(controller)),
        ],
      ),
    );
  }

  Widget _buildPageView(M3UHomeController controller) {
    return IndexedStack(
      index: controller.currentIndex,
      children: _buildPages(controller),
    );
  }

  List<Widget> _buildPages(M3UHomeController controller) {
    return [
      WatchHistoryScreen(
        key: ValueKey('watch_history_${controller.currentIndex}'),
        playlistId: widget.playlist.id,
      ),
      M3uItemsScreen(m3uItems: controller.m3uItems!),
      // _buildContentPage(controller.liveCategories!, controller),
      // _buildContentPage(controller.vodCategories!, controller),
      // _buildContentPage(controller.seriesCategories!, controller),
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
    if (ResponsiveHelper.isDesktopOrTV(context)) {
      return _buildDesktopSliverAppBar(context);
    }

    return _buildMobileSliverAppBar(context, controller);
  }

  SliverAppBar _buildDesktopSliverAppBar(BuildContext context) {
    return SliverAppBar(
      title: SelectableText(
        context.loc.live_streams,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      floating: true,
      snap: true,
      elevation: 0,
    );
  }

  SliverAppBar _buildMobileSliverAppBar(
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
    return _getNavigationItems(context).map((item) {
      return BottomNavigationBarItem(icon: Icon(item.icon), label: item.label);
    }).toList();
  }

  Widget _buildDesktopNavigationBar(
    BuildContext context,
    M3UHomeController controller,
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
    M3UHomeController controller,
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
        right: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
      ),
    );
  }

  double _getNavigationWidth(double screenWidth) {
    return screenWidth >= _largeScreenBreakpoint
        ? _largeNavWidth
        : _defaultNavWidth;
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
      NavigationItem(icon: Icons.history, label: context.loc.history, index: 0),
      NavigationItem(icon: Icons.all_inbox, label: context.loc.all, index: 1),
      // NavigationItem(icon: Icons.live_tv, label: context.loc.live, index: 2),
      // NavigationItem(
      //   icon: Icons.movie_outlined,
      //   label: context.loc.movie,
      //   index: 3,
      // ),
      // NavigationItem(
      //   icon: Icons.tv,
      //   label: context.loc.series_plural,
      //   index: 4,
      // ),
      NavigationItem(
        icon: Icons.settings,
        label: context.loc.settings,
        index: 2,
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
