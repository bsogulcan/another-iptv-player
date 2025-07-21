import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/m3u_item.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';

class CategoryViewModel {
  final Category category;
  final List<ContentItem> contentItems;

  CategoryViewModel({required this.category, required this.contentItems});
}