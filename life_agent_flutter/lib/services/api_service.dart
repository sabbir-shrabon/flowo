import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/api_config.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    _dio.interceptors.add(_AuthInterceptor(_dio));
  }

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  Future<String?> _getAccessToken() async {
    final supabase = Supabase.instance.client;
    var session = supabase.auth.currentSession;
    if (session == null) return null;

    // Refresh before sending an expired or nearly expired JWT.
    final expiresAt = session.expiresAt;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt != null && expiresAt - now < 60) {
      try {
        final response = await supabase.auth.refreshSession();
        session = response.session;
      } catch (_) {
        // Keep the local session; let the request report its real error.
      }
    }
    return session?.accessToken;
  }

  Future<Options> _authOptions([Map<String, dynamic>? extraHeaders]) async {
    final token = await _getAccessToken();
    final headers = <String, dynamic>{...?extraHeaders};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return Options(headers: headers);
  }

  Future<T> get<T>(String path) async {
    final options = await _authOptions();
    final response = await _dio.get<T>(path, options: options);
    return response.data as T;
  }

  Future<T> post<T>(String path, Map<String, dynamic> body) async {
    final options = await _authOptions();
    final response = await _dio.post<T>(path, data: body, options: options);
    return response.data as T;
  }

  Future<T> patch<T>(String path, Map<String, dynamic> body) async {
    final options = await _authOptions();
    final response = await _dio.patch<T>(path, data: body, options: options);
    return response.data as T;
  }

  Future<T> delete<T>(String path) async {
    final options = await _authOptions();
    final response = await _dio.delete<T>(path, options: options);
    return response.data as T;
  }

  /// Convenience: GET returning decoded JSON map/list
  Future<dynamic> getJson(String path) async {
    final options = await _authOptions();
    final response = await _dio.get(path, options: options);
    return response.data;
  }

  /// Convenience: POST returning decoded JSON map/list
  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    final options = await _authOptions();
    final response = await _dio.post(path, data: body, options: options);
    return response.data;
  }

  /// Convenience: PATCH returning decoded JSON map/list
  Future<dynamic> patchJson(String path, Map<String, dynamic> body) async {
    final options = await _authOptions();
    final response = await _dio.patch(path, data: body, options: options);
    return response.data;
  }
}

/// Dio interceptor that handles 401 responses by refreshing the Supabase
/// session and retrying the original request exactly once.
class _AuthInterceptor extends Interceptor {
  /// The same Dio instance used by [ApiService] — reusing it keeps the
  /// baseUrl, timeouts and all other interceptors intact on the retry.
  final Dio _dio;
  const _AuthInterceptor(this._dio);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final is401 = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra['retriedAfterRefresh'] == true;

    if (is401 && !alreadyRetried) {
      debugPrint('[ApiService] 401 received — attempting session refresh');
      try {
        final supabase = Supabase.instance.client;
        await supabase.auth.refreshSession();
        final newToken = supabase.auth.currentSession?.accessToken;

        if (newToken != null) {
          debugPrint('[ApiService] Session refreshed — retrying request');
          // Mark so we don't loop if the server keeps returning 401.
          err.requestOptions.extra['retriedAfterRefresh'] = true;
          err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          // Re-use the same configured Dio instance (keeps baseUrl + timeouts).
          final response = await _dio.fetch(err.requestOptions);
          return handler.resolve(response);
        } else {
          debugPrint('[ApiService] Refresh succeeded but no new token — passing error through');
        }
      } catch (refreshErr) {
        // Refresh failed entirely (e.g. refresh token revoked).
        // Pass the original 401 through; the UI will show the session error.
        debugPrint('[ApiService] Session refresh failed: $refreshErr');
      }
    }

    handler.next(err);
  }
}
