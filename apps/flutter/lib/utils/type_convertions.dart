int safeInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 0;
    try {
      return double.parse(trimmed).toInt();
    } catch (e) {
      return 0;
    }
  }
  try {
    return int.parse(value.toString());
  } catch (e) {
    return 0;
  }
}

double? safeDouble(dynamic value) {
  if (value == null) return null;

  if (value is double) return value;
  if (value is int) return value.toDouble();

  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    try {
      return double.parse(trimmed);
    } catch (e) {
      print('Double parsing error for value: "$value" - $e');
      return null;
    }
  }

  try {
    return double.parse(value.toString());
  } catch (e) {
    print('Double parsing error for value: "$value" - $e');
    return null;
  }
}

bool safeBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;

  if (value is String) {
    final trimmed = value.trim().toLowerCase();
    return trimmed == 'true' || trimmed == '1' || trimmed == 'yes';
  }

  if (value is int) return value != 0;

  return false;
}

String safeString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  return value.toString().trim();
}

String? getFirstBackdropPath(dynamic backdropPath) {
  if (backdropPath == null) return null;

  if (backdropPath is List && backdropPath.isNotEmpty) {
    final first = backdropPath[0];
    final safeFirst = safeString(first);
    return safeFirst.isEmpty ? null : safeFirst;
  }

  if (backdropPath is String) {
    final safe = safeString(backdropPath);
    return safe.isEmpty ? null : safe;
  }

  return null;
}
