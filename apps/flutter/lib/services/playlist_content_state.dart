import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import '../models/content_type.dart';

class PlaylistContentState {
  // Kategori bazlı canlı yayınlar
  static Map<String, List<ContentItem>> liveStreamsByCategory = {};
  
  // Kategori bazlı filmler
  static Map<String, List<ContentItem>> moviesByCategory = {};
  
  // Kategori bazlı diziler
  static Map<String, List<ContentItem>> seriesByCategory = {};
  
  // Tüm kategoriler
  static List<Category> liveCategories = [];
  static List<Category> movieCategories = [];
  static List<Category> seriesCategories = [];
  
  // Tüm içerikler (kategori olmadan)
  static List<ContentItem> allLiveStreams = [];
  static List<ContentItem> allMovies = [];
  static List<ContentItem> allSeries = [];

  // Canlı yayın kategorilerini ve içeriklerini yükle
  static Future<void> loadLiveStreams() async {
    liveStreamsByCategory.clear();
    allLiveStreams.clear();
    liveCategories.clear();

    try {
      final repository = AppState.xtreamCodeRepository ?? AppState.m3uRepository;
      if (repository == null) return;

      // Kategorileri yükle
      if (AppState.xtreamCodeRepository != null) {
        liveCategories = await AppState.xtreamCodeRepository!.getLiveCategories() ?? [];
      } else if (AppState.m3uRepository != null) {
        final categories = await AppState.m3uRepository!.getCategories();
        liveCategories = categories?.where((c) => c.type == CategoryType.live).toList() ?? [];
      }

      // Her kategori için kanalları yükle
      for (var category in liveCategories) {
        List<ContentItem> items = [];
        
        if (AppState.xtreamCodeRepository != null) {
          final streams = await AppState.xtreamCodeRepository!.getLiveChannelsByCategoryId(
            categoryId: category.categoryId,
          );
          items = streams?.map((x) => ContentItem(
            x.streamId,
            x.name,
            x.streamIcon,
            ContentType.liveStream,
            liveStream: x,
          )).toList() ?? [];
        } else if (AppState.m3uRepository != null) {
          final m3uItems = await AppState.m3uRepository!.getM3uItemsByCategoryId(
            categoryId: category.categoryId,
            contentType: ContentType.liveStream,
          );
          items = m3uItems?.map((x) => ContentItem(
            x.id,
            x.name ?? 'NO NAME',
            x.tvgLogo ?? '',
            ContentType.liveStream,
            m3uItem: x,
          )).toList() ?? [];
        }

        liveStreamsByCategory[category.categoryId] = items;
        allLiveStreams.addAll(items);
      }
    } catch (e) {
      print('Error loading live streams: $e');
    }
  }

  // Film kategorilerini ve içeriklerini yükle
  static Future<void> loadMovies() async {
    moviesByCategory.clear();
    allMovies.clear();
    movieCategories.clear();

    try {
      if (AppState.xtreamCodeRepository == null) return;

      movieCategories = await AppState.xtreamCodeRepository!.getVodCategories() ?? [];

      for (var category in movieCategories) {
        final movies = await AppState.xtreamCodeRepository!.getMovies(
          categoryId: category.categoryId,
        );
        final items = movies?.map((x) => ContentItem(
          x.streamId,
          x.name,
          x.streamIcon,
          ContentType.vod,
          containerExtension: x.containerExtension,
          vodStream: x,
        )).toList() ?? [];

        moviesByCategory[category.categoryId] = items;
        allMovies.addAll(items);
      }
    } catch (e) {
      print('Error loading movies: $e');
    }
  }

  // Dizi kategorilerini ve içeriklerini yükle
  static Future<void> loadSeries() async {
    seriesByCategory.clear();
    allSeries.clear();
    seriesCategories.clear();

    try {
      if (AppState.xtreamCodeRepository == null) return;

      seriesCategories = await AppState.xtreamCodeRepository!.getSeriesCategories() ?? [];

      for (var category in seriesCategories) {
        final series = await AppState.xtreamCodeRepository!.getSeries(
          categoryId: category.categoryId,
        );
        final items = series?.map((x) => ContentItem(
          x.seriesId,
          x.name,
          x.cover ?? '',
          ContentType.series,
          seriesStream: x,
        )).toList() ?? [];

        seriesByCategory[category.categoryId] = items;
        allSeries.addAll(items);
      }
    } catch (e) {
      print('Error loading series: $e');
    }
  }

  // Tüm içerikleri yükle
  static Future<void> loadAll() async {
    await loadLiveStreams();
    await loadMovies();
    await loadSeries();
  }

  // Temizle
  static void clear() {
    liveStreamsByCategory.clear();
    moviesByCategory.clear();
    seriesByCategory.clear();
    liveCategories.clear();
    movieCategories.clear();
    seriesCategories.clear();
    allLiveStreams.clear();
    allMovies.clear();
    allSeries.clear();
  }

  // Belirli bir kategorideki canlı yayınları getir
  static List<ContentItem> getLiveStreamsByCategory(String categoryId) {
    return liveStreamsByCategory[categoryId] ?? [];
  }

  // Belirli bir kategorideki filmleri getir
  static List<ContentItem> getMoviesByCategory(String categoryId) {
    return moviesByCategory[categoryId] ?? [];
  }

  // Belirli bir kategorideki dizileri getir
  static List<ContentItem> getSeriesByCategory(String categoryId) {
    return seriesByCategory[categoryId] ?? [];
  }
}

