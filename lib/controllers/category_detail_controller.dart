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

  // State
  List<ContentItem> _contentItems = [];
  List<ContentItem> _filteredItems = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String? _errorMessage;

  // Getters
  List<ContentItem> get contentItems => _contentItems;
  List<ContentItem> get filteredItems => _filteredItems;
  List<ContentItem> get displayItems => _isSearching ? _filteredItems : _contentItems;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => displayItems.isEmpty && !_isLoading;

  // Actions
  Future<void> loadContent() async {
    try {
      _setLoading(true);
      _contentItems = await _contentService.fetchContentByCategory(category);
      _setLoading(false);
    } catch (error) {
      _setError(error.toString());
    }
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
          .where((item) => item.name.toLowerCase().contains(query.trim().toLowerCase()))
          .toList();
    }
    notifyListeners();
  }

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

  void sortItems(String order) {
    switch (order) {
      case "ascending":
        displayItems.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
        break;
      case "descending":
        displayItems.sort((a, b) => (b.name ?? '').compareTo(a.name ?? ''));
        break;
      case "release_date":
        displayItems.sort((a, b) {
          final dateA;
          final dateB;
          if (a.contentType.name=="series") {
            dateA = DateTime.tryParse(a.seriesStream?.releaseDate ?? '') ?? DateTime(1970);
            dateB = DateTime.tryParse(b.seriesStream?.releaseDate ?? '') ?? DateTime(1970);
          }else{
            dateA = a.vodStream?.createdAt?.millisecondsSinceEpoch.toDouble() ?? 0.0;
            dateB = b.vodStream?.createdAt?.millisecondsSinceEpoch.toDouble() ?? 0.0;
          }

          return dateB.compareTo(dateA);
        });
        break;
      case "rating":
        displayItems.sort((a, b) {
          final ratingA ;
          final ratingB ;
          if (a.contentType.name=="series") {
            ratingA = double.tryParse(a.seriesStream?.rating ?? '0') ?? 0.0;
            ratingB = double.tryParse(b.seriesStream?.rating ?? '0') ?? 0.0;
          }else{
            ratingA = double.tryParse(a.vodStream?.rating ?? '0') ?? 0.0;
            ratingB = double.tryParse(b.vodStream?.rating ?? '0') ?? 0.0;
          }
          return ratingB.compareTo(ratingA);
        });
        break;
    }
    notifyListeners();
  }
}