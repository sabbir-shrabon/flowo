import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/connectivity_service.dart';
import '../services/local_cache_service.dart';
import '../services/sync_service.dart';

/// Counter that increments to signal TodayScreen should refresh.
final todayRefreshProvider = StateProvider<int>((ref) => 0);

/// Counter that increments when a plan is adapted/updated from any screen.
/// TodayScreen listens to this to show a full loading spinner and ensure
/// data is up-to-date immediately after plan changes.
final todayAdaptRefreshProvider = StateProvider<int>((ref) => 0);

/// Counter that increments to signal conversation list should refresh.
final conversationsRefreshProvider = StateProvider<int>((ref) => 0);

/// ID of a conversation to load in ChatScreen. Set by drawer, consumed by ChatScreen.
final conversationToLoadProvider = StateProvider<String?>((ref) => null);

/// Pre-filled chat message (e.g. "I'm busy today" from TodayScreen).
final pendingChatMessageProvider = StateProvider<String?>((ref) => null);

/// Whether the sidebar is open (used on Desktop/Web to shift content).
final sidebarOpenProvider = StateProvider<bool>((ref) => true);

// ── Offline First Providers ───────────────────────────────────────────────────

final connectivityProvider = StreamProvider<bool>((ref) {
  return ConnectivityService().onConnectivityChanged;
});

final localCacheProvider = Provider<LocalCacheService>((ref) {
  return LocalCacheService.instance;
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService();
});
