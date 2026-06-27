import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'dart:io' show Platform;
import 'env.dart';

class ApiConfig {
  static String get baseUrl {
    final override = Env.apiBaseUrl.trim();
    if (override.isNotEmpty) return override;

    // Web/Windows → localhost; Android emulator → 10.0.2.2
    if (kIsWeb) {
      if (kDebugMode) {
        return 'http://localhost:8000';
      }
      throw StateError(
        'Missing API_BASE_URL. Provide it through --dart-define=API_BASE_URL or the Netlify site environment variables.',
      );
    }
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    } catch (_) {}
    return 'http://localhost:8000';
  }
}
