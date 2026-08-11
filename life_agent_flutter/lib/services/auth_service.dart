import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

class AuthService {
  AuthService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<void> signInWithGoogle() async {
    bool isSupported = false;
    if (kIsWeb) {
      isSupported = true;
    } else if (Platform.isAndroid || Platform.isIOS) {
      isSupported = true;
    }

    if (!isSupported) {
      throw UnsupportedError(
        'Google sign-in is currently configured for Android, iOS, and Web only.',
      );
    }

    String? clientId;
    String? serverClientId;

    if (kIsWeb) {
      clientId = Env.googleWebClientId;
    } else {
      clientId = Platform.isIOS ? Env.googleIosClientId : null;
      serverClientId = Env.googleWebClientId;
    }

    final googleSignIn = GoogleSignIn(
      clientId: clientId,
      serverClientId: serverClientId,
    );

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      // User canceled the sign-in
      return;
    }

    final googleAuth = await googleUser.authentication;
    final accessToken = googleAuth.accessToken;
    final idToken = googleAuth.idToken;

    if (idToken == null) {
      throw StateError('Missing ID Token from Google Sign-In.');
    }

    await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  Future<void> signOutGoogle() async {
    bool isSupported = false;
    if (kIsWeb) {
      isSupported = true;
    } else if (Platform.isAndroid || Platform.isIOS) {
      isSupported = true;
    }

    if (isSupported) {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
    }
    await _supabase.auth.signOut();
  }
}
