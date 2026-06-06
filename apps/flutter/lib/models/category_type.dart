enum CategoryType {
  live,
  vod,
  series;

  String get value {
    switch (this) {
      case CategoryType.live:
        return 'live';
      case CategoryType.vod:
        return 'vod';
      case CategoryType.series:
        return 'series';
    }
  }

  static CategoryType fromString(String value) {
    switch (value) {
      case 'live':
        return CategoryType.live;
      case 'vod':
        return CategoryType.vod;
      case 'series':
        return CategoryType.series;
      default:
        throw ArgumentError('Invalid category type: $value');
    }
  }
}
