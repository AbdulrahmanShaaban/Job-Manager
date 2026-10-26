import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'config.dart';

/// Thin, typed wrapper around Dio.
///
/// One HTTP client is used for the whole app (the spec says to pick one).
class ApiClient {
  ApiClient({String? baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
          headers: {'accept': 'application/json'},
          // We handle every status code ourselves so error shapes stay typed.
          validateStatus: (_) => true,
        ),
      );

  final Dio _dio;
  String? _token;

  String get baseUrl => _dio.options.baseUrl;

  void setToken(String? token) {
    _token = token;
  }

  String? get token => _token;

  /// Releases the underlying HTTP client.
  void close() => _dio.close(force: true);

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    Duration? timeout,
  }) {
    return _send(
      () => _dio.get<dynamic>(
        path,
        queryParameters: query,
        options: Options(headers: _headers(), receiveTimeout: timeout),
      ),
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Duration? timeout,
  }) {
    return _send(
      () => _dio.post<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(headers: _headers(), receiveTimeout: timeout),
      ),
    );
  }

  Future<Map<String, dynamic>> patch(String path, {Object? body}) {
    return _send(
      () => _dio.patch<dynamic>(path, data: body, options: Options(headers: _headers())),
    );
  }

  Future<void> delete(String path) async {
    await _send(
      () => _dio.delete<dynamic>(path, options: Options(headers: _headers())),
    );
  }

  /// Fetches a plain-text body (CSV export, for example).
  Future<String> getText(String path, {Map<String, dynamic>? query}) async {
    late final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        path,
        queryParameters: query,
        options: Options(
          headers: _headers(),
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (error) {
      throw _networkError(error);
    }

    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final data = response.data;
      return data is String ? data : data?.toString() ?? '';
    }
    throw _apiError(status, response.data);
  }

  /// Uploads a short audio turn for the free fallback pipeline.
  Future<Map<String, dynamic>> postAudio(
    String path, {
    required Uint8List bytes,
    required String mimeType,
    Map<String, dynamic>? query,
  }) {
    return _send(
      () => _dio.post<dynamic>(
        path,
        data: Stream.value(bytes),
        queryParameters: query,
        options: Options(
          headers: {..._headers(), 'content-type': mimeType, 'content-length': bytes.length},
          receiveTimeout: AppConfig.voiceTimeout,
        ),
      ),
    );
  }

  Map<String, String> _headers() {
    return {
      if (_token != null) 'authorization': 'Bearer $_token',
      'content-type': 'application/json',
    };
  }

  Future<Map<String, dynamic>> _send(
    Future<Response<dynamic>> Function() request,
  ) async {
    late final Response<dynamic> response;
    try {
      response = await request();
    } on DioException catch (error) {
      throw _networkError(error);
    }

    final status = response.statusCode ?? 0;
    final data = response.data;

    if (status >= 200 && status < 300) {
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return const {};
    }

    throw _apiError(status, data);
  }

  ApiException _apiError(int status, dynamic data) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        return ApiException(
          statusCode: status,
          code: (error['code'] as String?) ?? 'UNKNOWN',
          message: (error['message'] as String?) ?? 'Request failed',
          details: error['details'],
        );
      }
    }
    if (data is String && data.trim().isNotEmpty && !data.trimLeft().startsWith('<')) {
      return ApiException(statusCode: status, code: 'HTTP_$status', message: data);
    }
    return ApiException(
      statusCode: status,
      code: 'HTTP_$status',
      message: status == 404
          ? 'المسار غير موجود على السيرفر.'
          : 'حصل خطأ في السيرفر. جرّب تاني.',
    );
  }

  ApiException _networkError(DioException error) {
    final type = error.type;
    final message = switch (type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => 'الاتصال بالسيرفر بطيء أو مقطوع. بياناتك محفوظة على الموبايل.',
      DioExceptionType.connectionError => 'مفيش اتصال بالإنترنت. هنسجّل كل حاجة على الموبايل لحد ما الشبكة ترجع.',
      DioExceptionType.badCertificate => 'شهادة السيرفر غير صالحة.',
      DioExceptionType.cancel => 'تم إلغاء الطلب.',
      _ => 'تعذر الوصول للسيرفر. جرّب تاني.',
    };
    return ApiException(
      message: message,
      code: 'NETWORK_ERROR',
      isNetworkError: true,
      details: error.message,
    );
  }
}
