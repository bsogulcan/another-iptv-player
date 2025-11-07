import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/category_view_model.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import '../services/content_service.dart';

class CategoryDetailController extends ChangeNotifier {
  final CategoryViewModel category;
  final ContentService _contentService = ContentService();

  CategoryDetailController(this.category) {
    loadContent();
  }

  // --- State ---
  List<ContentItem> _contentItems = [];
  List<ContentItem> _filteredItems = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String? _errorMessage;

  // --- Genre filtering ---
  List<String> _genres = [];
  String? _selectedGenre;

  // --- Getters ---
  List<ContentItem> get contentItems => _contentItems;
  List<ContentItem> get filteredItems => _filteredItems;
  List<ContentItem> get displayItems =>
      _isSearching ? _filteredItems : _applyGenreFilter(_contentItems);
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => displayItems.isEmpty && !_isLoading;

  List<String> get genres => _genres;
  String? get selectedGenre => _selectedGenre;

  Future<void> loadContent() async {
    try {
      _setLoading(true);
      _contentItems = await _contentService.fetchContentByCategory(category);
      _genres = _extractGenres(_contentItems);
      _selectedGenre = null;
      _setLoading(false);
    } catch (error) {
      _setError(error.toString());
    }
  }

  List<String> _extractGenres(List<ContentItem> items) {
    final Set<String> genreSet = {};

    for (final item in items) {
      final rawGenre = _getItemGenre(item);
      if (rawGenre != null && rawGenre.isNotEmpty) {
        final parts = rawGenre
            .split(',')
            .map((g) => g.trim().toLowerCase())
            .where((g) => g.isNotEmpty)
            .toSet();
        genreSet.addAll(parts);
      }
    }

    final sorted = genreSet.toList()..sort();
    return sorted;
  }

  String? _getItemGenre(ContentItem item) {
    if (item.contentType.name == "series") {
      return item.seriesStream?.genre;
    } else {
      return item.vodStream?.genre;
    }
  }

  void filterByGenre(String? genre) {
    _selectedGenre = genre;
    notifyListeners();
  }

  List<ContentItem> _applyGenreFilter(List<ContentItem> items) {
    if (_selectedGenre == null || _selectedGenre!.isEmpty) return items;

    final genreLower = _selectedGenre!.toLowerCase();
    return items.where((item) {
      final genres = _getItemGenre(item)?.toLowerCase() ?? '';
      return genres.split(',').map((g) => g.trim()).contains(genreLower);
    }).toList();
  }

  void startSearch() {
    _isSearching = true;
    _filteredItems = [];
    notifyListeners();
  }

  void stopSearch() {
    _isSearching = false;
    _filteredItems = [];
    notifyListeners();
  }

  void searchContent(String query) {
    if (query.trim().isEmpty) {
      _filteredItems = [];
    } else {
      _filteredItems = _contentItems
          .where((item) =>
          (item.name ?? '').toLowerCase().contains(query.trim().toLowerCase()))
          .toList();
    }
    notifyListeners();
  }

  void sortItems(String order) {
    final list = displayItems;

    switch (order) {
      case "ascending":
        list.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
        break;
      case "descending":
        list.sort((a, b) => (b.name ?? '').compareTo(a.name ?? ''));
        break;
      case "release_date":
        list.sort((a, b) {
          final dateA;
          final dateB;
          if (a.contentType.name == "series") {
            dateA = DateTime.tryParse(a.seriesStream?.releaseDate ?? '') ?? DateTime(1970);
            dateB = DateTime.tryParse(b.seriesStream?.releaseDate ?? '') ?? DateTime(1970);
          } else {
            dateA = a.vodStream?.createdAt?.millisecondsSinceEpoch.toDouble() ?? 0.0;
            dateB = b.vodStream?.createdAt?.millisecondsSinceEpoch.toDouble() ?? 0.0;
          }
          return dateB.compareTo(dateA);
        });
        break;
      case "rating":
        list.sort((a, b) {
          final ratingA;
          final ratingB;
          if (a.contentType.name == "series") {
            ratingA = double.tryParse(a.seriesStream?.rating ?? '0') ?? 0.0;
            ratingB = double.tryParse(b.seriesStream?.rating ?? '0') ?? 0.0;
          } else {
            ratingA = double.tryParse(a.vodStream?.rating ?? '0') ?? 0.0;
            ratingB = double.tryParse(b.vodStream?.rating ?? '0') ?? 0.0;
          }
          return ratingB.compareTo(ratingA);
        });
        break;
    }

    notifyListeners();
  }

  // --- State helpers ---
  void _setLoading(bool loading) {
    _isLoading = loading;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String error) {
    _isLoading = false;
    _errorMessage = error;
    notifyListeners();
  }
}
