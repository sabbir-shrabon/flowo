import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/local_cache_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error handlers
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformError: $error');
    return true;
  };

  try {
    // NOTE: SupabaseConfig reads from build-time `--dart-define` via `Env`.
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );

    // Initialize Hive and Local Cache Service
    await Hive.initFlutter();
    await LocalCacheService.instance.init();

    runApp(const ProviderScope(child: LifeAgentApp()));
  } catch (error, stack) {
    debugPrint('StartupError: $error');
    debugPrintStack(stackTrace: stack);
    runApp(StartupErrorApp(error: error));
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = error.toString();
    final missingBuildConfig =
        message.contains('SUPABASE_URL') ||
        message.contains('SUPABASE_ANON_KEY') ||
        message.contains('API_BASE_URL') ||
        message.contains('GOOGLE_WEB_CLIENT_ID');

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF6F4EE),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Color(0xFFDDD6C8)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        missingBuildConfig
                            ? 'Missing web build configuration'
                            : 'App startup failed',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        missingBuildConfig
                            ? 'This build is missing one or more required --dart-define values. Rebuild the Flutter web app with SUPABASE_URL, SUPABASE_ANON_KEY, API_BASE_URL, and GOOGLE_WEB_CLIENT_ID before deploying to Netlify.'
                            : 'The app hit an error during initialization. The details below should help narrow it down.',
                      ),
                      const SizedBox(height: 16),
                      SelectableText(message),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
