import '../core/formatting.dart';

/// Shared JSON coercion helpers. The API is trusted but defensive parsing keeps
/// one malformed field from crashing a whole screen.
String? asString(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  return value.toString();
}

String asRequiredString(Object? value, [String fallback = '']) {
  return asString(value) ?? fallback;
}

int asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double? asDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

DateTime? asDateTime(Object? value) {
  final text = asString(value);
  if (text == null) return null;
  return DateTime.tryParse(text);
}

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Map<String, dynamic>> asMapList(Object? value) {
  if (value is List) {
    return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false);
  }
  return const [];
}

/// A date-only calendar day, kept as an ISO string end-to-end.
String? asDateOnly(Object? value) {
  final text = asString(value);
  if (text == null) return null;
  final parsed = AppFormat.parseDateOnly(text);
  if (parsed == null) return null;
  return AppFormat.isoDate(parsed);
}
