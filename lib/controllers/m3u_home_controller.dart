import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/category_view_model.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/m3u_item.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/view_state.dart';
import 'package:another_iptv_player/repositories/m3u_repository.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:flutter/material.dart';

class M3UHomeController extends ChangeNotifier {
  late PageController _pageController;
  final M3uRepository _repository = AppState.m3uRepository!;
  String? _errorMessage;
  ViewState _viewState = ViewState.idle;

  int _currentIndex = 0;
  bool _isLoading = true;

  final List<CategoryViewModel> _liveCategories = [];
  final List<CategoryViewModel> _vodCategories = [];
  final List<CategoryViewModel> _seriesCategories = [];
  List<M3uItem>? _m3uItems = [];
  List<M3uItem>? _liveChannels;
  List<M3uItem>? _movies;
  List<M3uItem>? _series;

  // Getters
  PageController get pageController => _pageController;

  int get currentIndex => _currentIndex;

  List<CategoryViewModel>? get liveCategories => _liveCategories;

  List<CategoryViewModel>? get vodCategories => _vodCategories;

  List<CategoryViewModel>? get seriesCategories => _seriesCategories;

  List<M3uItem>? get m3uItems => _m3uItems;

  List<M3uItem>? get liveChannels => _liveChannels;

  List<M3uItem>? get movies => _movies;

  List<M3uItem>? get series => _series;

  bool get isLoading => _isLoading;

  M3UHomeController() {
    _pageController = PageController();
    _loadM3uItems();
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
        return context.loc.all;
      case 2:
        return context.loc.live_streams;
      case 3:
        return context.loc.movies;
      case 4:
        return context.loc.series_plural;
      case 5:
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

  Future<void> _loadM3uItems() async {
    try {
      _isLoading = true;
      notifyListeners();

      _m3uItems = await _repository.getM3uItems();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'M3U items cannot loaded: $e';
      _setViewState(ViewState.error);
      _isLoading = false;
    }
  }

  Future<void> _loadCategories() async {
    try {
      _isLoading = true;
      notifyListeners();

      var categories = await _repository.getCategories();
      for (var category in categories!) {
        if (category.type != CategoryType.series) {
          var m3uItems = await _repository.getM3uItemsByCategoryId(
            categoryId: category.categoryId,
            top: 10,
          );

          late CategoryViewModel categoryViewModel;
          if (m3uItems == null) {
            categoryViewModel = CategoryViewModel(
              category: category,
              contentItems: [],
            );
          } else {
            categoryViewModel = CategoryViewModel(
              category: category,
              contentItems: m3uItems.map((x) {
                return ContentItem(
                  x.url,
                  x.name ?? '',
                  x.tvgLogo ?? '',
                  x.contentType,
                  m3uItem: x,
                );
              }).toList(),
            );
          }

          switch (category.type) {
            case CategoryType.live:
              _liveCategories.add(categoryViewModel);
            case CategoryType.vod:
              _vodCategories.add(categoryViewModel);
            case CategoryType.series:
              _seriesCategories.add(categoryViewModel);
          }
        } else {
          var series = await _repository.getSeriesByCategoryId(
            categoryId: category.categoryId,
            top: 10,
          );

          late CategoryViewModel categoryViewModel;
          if (series == null) {
            categoryViewModel = CategoryViewModel(
              category: category,
              contentItems: [],
            );
          } else {
            categoryViewModel = CategoryViewModel(
              category: category,
              contentItems: series.map((x) {
                return ContentItem(x.seriesId, x.name, '', ContentType.series);
              }).toList(),
            );
          }

          _seriesCategories.add(categoryViewModel);
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Kategoriler yüklenemedi: $e';
      _setViewState(ViewState.error);
      _isLoading = false;
    }
  }
}
