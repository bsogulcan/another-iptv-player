import 'package:flutter/foundation.dart' hide Category;
import 'package:another_iptv_player/models/api_response.dart';
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/live_stream.dart';
import 'package:another_iptv_player/models/vod_streams.dart';
import 'package:another_iptv_player/models/progress_step.dart';
import 'package:another_iptv_player/models/series.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';

class IptvController extends ChangeNotifier {
  final IptvRepository _repository;
  bool refreshAll = false;

  IptvController(this._repository, this.refreshAll);

  // State
  ApiResponse? _userInfo;
  List<Category>? _liveCategories;
  List<Category>? _vodCategories;
  List<Category>? _seriesCategories;
  List<LiveStream>? _liveChannels;
  List<VodStream>? _movies;
  List<SeriesStream>? _series;

  bool _isLoading = false;
  String? _errorMessage;
  ProgressStep _currentStep = ProgressStep.userInfo;

  // Getters
  ApiResponse? get userInfo => _userInfo;
  // Getters
  List<Category>? get liveCategories => _liveCategories;
  List<Category>? get vodCategories => _vodCategories;
  List<Category>? get seriesCategories => _seriesCategories;
  List<LiveStream>? get liveChannels => _liveChannels;
  List<VodStream>? get movies => _movies;
  List<SeriesStream>? get series => _series;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ProgressStep get currentStep => _currentStep;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _setCurrentStep(ProgressStep step) {
    _currentStep = step;
    notifyListeners();
  }

  Future<bool> loadUserInfo() async {
    try {
      _setCurrentStep(ProgressStep.userInfo);
      _setError(null);

      _userInfo = await _repository.getPlayerInfo(forceRefresh: refreshAll);

      if (_userInfo == null) {
        throw Exception('Kullanıcı bilgileri alınamadı');
      }

      return true;
    } catch (e) {
      _setError('Kullanıcı bilgileri yüklenirken hata: $e');
      return false;
    }
  }

  // Kategorileri yükle
  Future<bool> loadCategories() async {
    try {
      _setCurrentStep(ProgressStep.categories);

      final categoriesMap = await _repository.getAllCategories(forceRefresh: refreshAll);

      if (categoriesMap != null) {
        _liveCategories = categoriesMap[CategoryType.live] ?? [];
        _vodCategories = categoriesMap[CategoryType.vod] ?? [];
        _seriesCategories = categoriesMap[CategoryType.series] ?? [];

        notifyListeners();
        return true;
      }

      return false;
    } catch (e) {
      _setError('Kategoriler yüklenemedi: $e');
      return false;
    }
  }

  // Tek tip kategori yükle
  Future<bool> loadCategoriesByType(CategoryType type) async {
    try {
      List<Category>? categories;

      switch (type) {
        case CategoryType.live:
          categories = await _repository.getLiveCategories(forceRefresh: refreshAll);
          if (categories != null) _liveCategories = categories;
          break;
        case CategoryType.vod:
          categories = await _repository.getVodCategories(forceRefresh: refreshAll);
          if (categories != null) _vodCategories = categories;
          break;
        case CategoryType.series:
          categories = await _repository.getSeriesCategories(forceRefresh: refreshAll);
          if (categories != null) _seriesCategories = categories;
          break;
      }

      notifyListeners();
      return categories != null;
    } catch (e) {
      _setError('${type.value} kategorileri yüklenemedi: $e');
      return false;
    }
  }

  Future<bool> loadLiveChannels() async {
    try {
      _setCurrentStep(ProgressStep.liveChannels);
      _setError(null);

      _liveChannels = await _repository.getLiveChannels();

      if (_liveChannels == null) {
        throw Exception('Canlı kanallar alınamadı');
      }

      return true;
    } catch (e) {
      _setError('Canlı kanallar yüklenirken hata: $e');
      return false;
    }
  }

  Future<bool> loadMovies() async {
    try {
      _setCurrentStep(ProgressStep.movies);
      _setError(null);

      _movies = await _repository.getMovies();

      if (_movies == null) {
        throw Exception('Filmler alınamadı');
      }

      return true;
    } catch (e) {
      _setError('Filmler yüklenirken hata: $e');
      return false;
    }
  }

  Future<bool> loadSeries() async {
    try {
      _setCurrentStep(ProgressStep.series);
      _setError(null);

      _series = await _repository.getSeries();

      if (_series == null) {
        throw Exception('Diziler alınamadı');
      }

      return true;
    } catch (e) {
      _setError('Diziler yüklenirken hata: $e');
      return false;
    }
  }

  Future<bool> loadAllData() async {
    _setLoading(true);

    bool success = true;

    success &= await loadUserInfo();
    if (!success) {
      _setLoading(false);
      return false;
    }

    success &= await loadCategories();
    if (!success) {
      _setLoading(false);
      return false;
    }

    success &= await loadLiveChannels();
    if (!success) {
      _setLoading(false);
      return false;
    }

    success &= await loadMovies();
    if (!success) {
      _setLoading(false);
      return false;
    }

    success &= await loadSeries();

    _setLoading(false);
    return success;
  }

  void retry() {
    _setError(null);
    _setCurrentStep(ProgressStep.userInfo);
    loadAllData();
  }

  void reset() {
    _userInfo = null;
    _liveCategories = null;
    _vodCategories = null;
    _seriesCategories = null;
    _liveChannels = null;
    _movies = null;
    _series = null;
    _isLoading = false;
    _errorMessage = null;
    _currentStep = ProgressStep.userInfo;
    notifyListeners();
  }
}
