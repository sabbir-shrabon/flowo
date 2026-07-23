import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../services/local_cache_service.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AppAuthState {
  final AuthStatus status;
  final User? user;
  final Session? session;

  const AppAuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.session,
  });

  AppAuthState copyWith({AuthStatus? status, User? user, Session? session}) {
    return AppAuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      session: session ?? this.session,
    );
  }
}

class AuthNotifier extends StateNotifier<AppAuthState> {
  final SupabaseClient _supabase;
  final AuthService _authService;
  late final StreamSubscription<dynamic> _authSub;

  AuthNotifier(this._supabase, this._authService)
    : super(const AppAuthState()) {
    _init();
  }

  void _init() {
    // Check existing session
    final currentSession = _supabase.auth.currentSession;
    if (currentSession != null) {
      state = AppAuthState(
        status: AuthStatus.authenticated,
        user: currentSession.user,
        session: currentSession,
      );
    } else {
      state = const AppAuthState(status: AuthStatus.unauthenticated);
    }

    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        state = AppAuthState(
          status: AuthStatus.authenticated,
          user: session.user,
          session: session,
        );
      } else {
        state = const AppAuthState(status: AuthStatus.unauthenticated);
      }
    });
  }

  Future<void> signIn(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final session = response.session;
    if (session != null) {
      state = AppAuthState(
        status: AuthStatus.authenticated,
        user: session.user,
        session: session,
      );
    }
  }

  Future<void> signUp(String email, String password) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );
    final session = response.session;
    if (session != null) {
      state = AppAuthState(
        status: AuthStatus.authenticated,
        user: session.user,
        session: session,
      );
    }
  }

  Future<void> signInWithGoogle() async {
    await _authService.signInWithGoogle();
  }

  Future<void> signOut() async {
    // Clear all cached data BEFORE signing out to ensure
    // fresh state for next user. This must be sequential.
    await LocalCacheService.instance.clearAll();
    await _authService.signOutGoogle();
    await _supabase.auth.signOut();
  }

  Future<String?> getToken() async {
    final session = _supabase.auth.currentSession;
    return session?.accessToken;
  }

  /// Check if session is valid and refresh if needed.
  /// Returns true if session is valid or was refreshed successfully.
  Future<bool> ensureValidSession() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return false;

    // Check if token is expired or about to expire (within 5 minutes)
    final expiresAt = session.expiresAt;
    if (expiresAt == null) return true; // No expiry info, assume valid
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt - now < 300) {
      // Token expired or expiring soon, try to refresh
      try {
        await _supabase.auth.refreshSession();
        return true;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AppAuthState>((ref) {
  final supabase = Supabase.instance.client;
  return AuthNotifier(supabase, AuthService(supabaseClient: supabase));
});
