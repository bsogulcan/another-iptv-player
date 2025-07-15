import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/utils/build_media_url.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/category_view_model.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/view_state.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:path/path.dart';

import '../screens/xtream-codes/xtream_code_data_loader_screen.dart';

class XtreamCodeHomeController extends ChangeNotifier {
  late PageController _pageController;
  final IptvRepository _repository = AppState.xtreamCodeRepository!;
  String? _errorMessage;
  ViewState _viewState = ViewState.idle;

  int _currentIndex = 0;
  final bool _isLoading = false;

  final List<CategoryViewModel> _liveCategories = [];
  final List<CategoryViewModel> _movieCategories = [];
  final List<CategoryViewModel> _seriesCategories = [];

  // Getters
  PageController get pageController => _pageController;

  int get currentIndex => _currentIndex;

  bool get isLoading => _isLoading;

  List<CategoryViewModel>? get liveCategories => _liveCategories;

  List<CategoryViewModel>? get movieCategories => _movieCategories;

  List<CategoryViewModel>? get seriesCategories => _seriesCategories;

  XtreamCodeHomeController() {
    _pageController = PageController();
    _loadCategories();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void onNavigationTap(int index) {
    _currentIndex = index;
    notifyListeners();

    _pageController.animateToPage(
      index,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void onPageChanged(int index) {
    _currentIndex = index;
    notifyListeners();
  }

  String getPageTitle(BuildContext context) {
    switch (currentIndex) {
      case 0:
        return context.loc.history;
      case 1:
        return context.loc.live_streams;
      case 2:
        return context.loc.movies;
      case 3:
        return context.loc.series_plural;
      case 4:
        return context.loc.settings;
      default:
        return 'Another IPTV Player';
    }
  }

  void _setViewState(ViewState state) {
    _viewState = state;
    if (state != ViewState.error) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  Future<void> _loadCategories() async {
    try {
      var liveCategories = await _repository.getLiveCategories();
      for (var liveCategory in liveCategories!) {
        var liveStreams = await _repository.getLiveChannelsByCategoryId(
          categoryId: liveCategory.categoryId,
          top: 10,
        );

        var categoryViewModel = CategoryViewModel(
          category: liveCategory,
          contentItems: liveStreams!
              .map(
                (x) => ContentItem(
                  x.streamId,
                  x.name,
                  x.streamIcon,
                  ContentType.liveStream,
                  liveStream: x,
                ),
              )
              .toList(),
        );
        _liveCategories.add(categoryViewModel);
      }

      var movieCategories = await _repository.getVodCategories();
      for (var movieCategory in movieCategories!) {
        var movies = await _repository.getMovies(
          categoryId: movieCategory.categoryId,
          top: 10,
        );

        var categoryViewModel = CategoryViewModel(
          category: movieCategory,
          contentItems: movies!
              .map(
                (x) => ContentItem(
                  x.streamId,
                  x.name,
                  x.streamIcon,
                  ContentType.vod,
                  containerExtension: x.containerExtension,
                  vodStream: x,
                ),
              )
              .toList(),
        );

        _movieCategories.add(categoryViewModel);
      }

      var seriesCategories = await _repository.getSeriesCategories();
      for (var seriesCategory in seriesCategories!) {
        var series = await _repository.getSeries(
          categoryId: seriesCategory.categoryId,
          top: 10,
        );

        var categoryViewModel = CategoryViewModel(
          category: seriesCategory,
          contentItems: series!
              .map(
                (x) => ContentItem(
                  x.seriesId,
                  x.name,
                  x.cover ?? '',
                  ContentType.series,
                  seriesStream: x,
                ),
              )
              .toList(),
        );
        _seriesCategories.add(categoryViewModel);
      }

      notifyListeners();
    } catch (e) {
      _errorMessage = 'Kategoriler yüklenemedi: $e';
      _setViewState(ViewState.error);
    }
  }

  refreshAllData(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => XtreamCodeDataLoaderScreen(
          playlist: AppState.currentPlaylist!,
          refreshAll: true,
        ),
      ),
    );
  }
}
