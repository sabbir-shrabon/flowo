import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../services/local_cache_service.dart';

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
  late final StreamSubscription<dynamic> _authSub;

  AuthNotifier(this._supabase) : super(const AppAuthState()) {
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
    await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp(String email, String password) async {
    await _supabase.auth.signUp(email: email, password: password);
  }

  Future<void> signOut() async {
    // Clear all cached data BEFORE signing out to ensure
    // fresh state for next user. This must be sequential.
    await LocalCacheService.instance.clearAll();
    await _supabase.auth.signOut();
  }

  Future<String?> getToken() async {
    final session = _supabase.auth.currentSession;
    return session?.accessToken;
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AppAuthState>((ref) {
  return AuthNotifier(Supabase.instance.client);
});
