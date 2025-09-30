import 'package:drift/drift.dart';
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/utils/type_convertions.dart';
import 'category_type.dart';

class Category {
  final String categoryId;
  final String categoryName;
  final int parentId;
  final String playlistId;
  final CategoryType type;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Category({
    required this.categoryId,
    required this.categoryName,
    required this.parentId,
    required this.playlistId,
    required this.type,
    this.createdAt,
    this.updatedAt,
  });

  factory Category.fromJson(
      Map<String, dynamic> json,
      String playlistId,
      CategoryType type,
      ) {
    return Category(
      categoryId: safeString(json['category_id']),
      categoryName: safeString(json['category_name']),
      parentId: safeInt(json['parent_id']),
      playlistId: safeString(playlistId),
      type: type,
    );
  }

  factory Category.fromDrift(CategoriesData driftObject) {
    return Category(
      categoryId: driftObject.categoryId,
      categoryName: driftObject.categoryName,
      parentId: driftObject.parentId,
      playlistId: driftObject.playlistId,
      type: CategoryType.fromString(driftObject.type),
      createdAt: driftObject.createdAt,
      updatedAt: driftObject.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category_id': categoryId,
      'category_name': categoryName,
      'parent_id': parentId,
      'playlist_id': playlistId,
      'type': type.value,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  CategoriesCompanion toCompanion() {
    return CategoriesCompanion(
      categoryId: Value(categoryId),
      categoryName: Value(categoryName),
      parentId: Value(parentId),
      playlistId: Value(playlistId),
      type: Value(type.value),
      updatedAt: Value(DateTime.now()),
    );
  }

  @override
  String toString() {
    return 'Category(categoryId: $categoryId, categoryName: $categoryName, parentId: $parentId, playlistId: $playlistId, type: ${type.value})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Category &&
        other.categoryId == categoryId &&
        other.categoryName == categoryName &&
        other.parentId == parentId &&
        other.playlistId == playlistId &&
        other.type == type;
  }

  @override
  int get hashCode =>
      categoryId.hashCode ^
      categoryName.hashCode ^
      parentId.hashCode ^
      playlistId.hashCode ^
      type.hashCode;
}
