import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/category_view_model.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/view_state.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';
import 'package:another_iptv_player/services/app_state.dart';
import '../repositories/user_preferences.dart';
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

  // --- Categoriy hidden ---
  final Set<String> _hiddenMovieCategoryIds = {};
  final Set<String> _hiddenSeriesCategoryIds = {};

  // Getters publics
  Set<String> get hiddenMovieCategoryIds => _hiddenMovieCategoryIds;
  Set<String> get hiddenSeriesCategoryIds => _hiddenSeriesCategoryIds;

  // Fonctions toggle
  void toggleMovieCategoryVisibility(String categoryId) {
    if (_hiddenMovieCategoryIds.contains(categoryId)) {
      _hiddenMovieCategoryIds.remove(categoryId);
    } else {
      _hiddenMovieCategoryIds.add(categoryId);
    }
    notifyListeners();
  }

  void toggleSeriesCategoryVisibility(String categoryId) {
    if (_hiddenSeriesCategoryIds.contains(categoryId)) {
      _hiddenSeriesCategoryIds.remove(categoryId);
    } else {
      _hiddenSeriesCategoryIds.add(categoryId);
    }
    notifyListeners();
  }

  // Getters filtrés
  List<CategoryViewModel> get visibleMovieCategories => _movieCategories
      .where((c) => !_hiddenMovieCategoryIds.contains(c.category.categoryId))
      .toList();

  List<CategoryViewModel> get visibleSeriesCategories => _seriesCategories
      .where((c) => !_hiddenSeriesCategoryIds.contains(c.category.categoryId))
      .toList();

  // Getters
  PageController get pageController => _pageController;

  int get currentIndex => _currentIndex;

  bool get isLoading => _isLoading;

  List<CategoryViewModel>? get liveCategories => _liveCategories;

  List<CategoryViewModel> get movieCategories => _movieCategories;

  List<CategoryViewModel> get seriesCategories => _seriesCategories;

  XtreamCodeHomeController(bool all) {
    _pageController = PageController();
    _loadCategories(all);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void onNavigationTap(int index) {
    _currentIndex = index;
    notifyListeners();

    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
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

  Future<void> _loadCategories(bool all) async {
    try {
      var liveCategories = await _repository.getLiveCategories();
      if (liveCategories != null && liveCategories.isNotEmpty) {
        for (var liveCategory in liveCategories) {
          var liveStreams = await _repository.getLiveChannelsByCategoryId(
            categoryId: liveCategory.categoryId,
            top: 10,
          );

          if (liveStreams == null || liveStreams.isEmpty) continue;

          var categoryViewModel = CategoryViewModel(
            category: liveCategory,
            contentItems: liveStreams
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
          if (!all) {
            if (!await UserPreferences.getHiddenCategory(
              liveCategory.categoryId,
            )) {
              _liveCategories.add(categoryViewModel);
            }
          } else {
            _liveCategories.add(categoryViewModel);
          }
        }
      }

      var movieCategories = await _repository.getVodCategories();
      if (movieCategories != null && movieCategories.isNotEmpty) {
        for (var movieCategory in movieCategories) {
          var movies = await _repository.getMovies(
            categoryId: movieCategory.categoryId,
            top: 10,
          );

          if (movies == null || movies.isEmpty) {
            continue;
          }

          var categoryViewModel = CategoryViewModel(
            category: movieCategory,
            contentItems: movies
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
          if (!all) {
            if (!await UserPreferences.getHiddenCategory(
              movieCategory.categoryId,
            )) {
              _movieCategories.add(categoryViewModel);
            }
          } else {
            _movieCategories.add(categoryViewModel);
          }
        }
      }

      var seriesCategories = await _repository.getSeriesCategories();
      if (seriesCategories != null && seriesCategories.isNotEmpty) {
        for (var seriesCategory in seriesCategories) {
          var series = await _repository.getSeries(
            categoryId: seriesCategory.categoryId,
            top: 10,
          );

          if (series == null || series.isEmpty) {
            continue;
          }

          var categoryViewModel = CategoryViewModel(
            category: seriesCategory,
            contentItems: series
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
          if (!all) {
            if (!await UserPreferences.getHiddenCategory(
              seriesCategory.categoryId,
            )) {
              _seriesCategories.add(categoryViewModel);
            }
          } else {
            _seriesCategories.add(categoryViewModel);
          }
        }
      }

      notifyListeners();
    } catch (e, st) {
      debugPrint(st.toString());
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
