/// A typed failure coming from the API or the network layer.
class ApiException implements Exception {
  ApiException({
    required this.message,
    this.code = 'UNKNOWN',
    this.statusCode,
    this.details,
    this.isNetworkError = false,
  });

  final String message;
  final String code;
  final int? statusCode;
  final Object? details;
  final bool isNetworkError;

  bool get isUnauthorized => statusCode == 401;
  bool get isConflict => statusCode == 409 || code == 'CONFLICT';
  bool get isValidation => statusCode == 422 || code == 'VALIDATION_ERROR';
  bool get isAiUnavailable => code == 'AI_UNAVAILABLE' || code == 'AI_QUOTA_EXHAUSTED';

  /// The server may attach `{ serverUpdatedAt }` on optimistic-concurrency
  /// conflicts so the client can explain what changed.
  String? get serverUpdatedAt {
    final value = details;
    if (value is Map && value['serverUpdatedAt'] is String) {
      return value['serverUpdatedAt'] as String;
    }
    return null;
  }

  /// Validation details may arrive as a list of `{path, message}` or as a
  /// single `{field, message}` object.
  String? get validationMessage {
    final value = details;
    if (value is Map && value['message'] is String) {
      return value['message'] as String;
    }
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is Map && first['message'] is String) {
        return first['message'] as String;
      }
    }
    return null;
  }

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
