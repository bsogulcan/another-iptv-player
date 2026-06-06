import 'category_type.dart';

enum ContentType {
  liveStream,
  vod,
  series;

  static CategoryType toCategoryType(ContentType contentType) {
    switch (contentType) {
      case ContentType.liveStream:
        return CategoryType.live;
      case ContentType.vod:
        return CategoryType.vod;
      case ContentType.series:
        return CategoryType.series;
    }
  }
}
