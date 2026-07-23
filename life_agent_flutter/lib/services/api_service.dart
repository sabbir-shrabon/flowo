import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/api_config.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    _dio.interceptors.add(_AuthInterceptor());
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

/// Dio interceptor that handles 401 responses.
class _AuthInterceptor extends Interceptor {
  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 &&
        err.requestOptions.extra['retriedAfterRefresh'] != true) {
      try {
        final supabase = Supabase.instance.client;
        await supabase.auth.refreshSession();
        final newToken = supabase.auth.currentSession?.accessToken;

        if (newToken != null) {
          err.requestOptions.extra['retriedAfterRefresh'] = true;
          err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          final response = await Dio().fetch(err.requestOptions);
          return handler.resolve(response);
        }
      } catch (_) {
        // Do not sign out on an API 401. It may be a backend JWT configuration issue.
      }
    }

    handler.next(err);
  }
}
