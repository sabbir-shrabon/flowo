import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;
  static const _mobileGoogleRedirect = 'com.lifeagent.life_agent_flutter://login-callback/';

  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      final redirectTo = Uri(
        scheme: Uri.base.scheme,
        host: Uri.base.host,
        port: Uri.base.hasPort ? Uri.base.port : null,
        path: Uri.base.path.isEmpty ? '/' : Uri.base.path,
      ).toString();

      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
      );
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError(
        'Google sign-in is currently configured for Android, iOS, and Web only.',
      );
    }

    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _mobileGoogleRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signOutGoogle() async {}
}
