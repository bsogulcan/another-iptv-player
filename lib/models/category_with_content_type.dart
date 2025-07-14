import 'package:another_iptv_player/models/content_type.dart';

class CategoryWithContentType {
  final String categoryName;
  final ContentType contentType;

  const CategoryWithContentType({required this.categoryName, required this.contentType});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryWithContentType &&
          runtimeType == other.runtimeType &&
          categoryName == other.categoryName &&
          contentType == other.contentType;

  @override
  int get hashCode => categoryName.hashCode ^ contentType.hashCode;

  @override
  String toString() => '$categoryName - $contentType';
}
