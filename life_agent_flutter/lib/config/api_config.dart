import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'dart:io' show Platform;
import 'env.dart';

class ApiConfig {
  static const String _productionWebBaseUrl = 'https://flowo-1.onrender.com';

  static String get baseUrl {
    final override = Env.apiBaseUrl.trim();
    if (override.isNotEmpty) return override;

    // Web/Windows → localhost; Android emulator → 10.0.2.2
    if (kIsWeb) {
      return kDebugMode ? 'http://localhost:8000' : _productionWebBaseUrl;
    }
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    } catch (_) {}
    return 'http://localhost:8000';
  }
}
