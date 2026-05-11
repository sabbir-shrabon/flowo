import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'widgets/animations.dart';
import 'providers/auth_provider.dart';
import 'screens/main_shell.dart';
import 'screens/today/today_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/memory/memory_screen.dart';
import 'screens/plans/plans_screen.dart';
import 'screens/plans/plan_roadmap_screen.dart';
import 'screens/plans/milestone_insight_screen.dart';
import 'screens/task_detail/task_detail_screen.dart';
import 'screens/history/history_screen.dart';
import 'theme/app_theme.dart';

/// GlobalKey for the root navigator — used by GoRouter.
final GlobalKey<NavigatorState> routerKey = GlobalKey<NavigatorState>();

// ── Theme mode provider ──
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

enum AppAccentColor { green, blue, ash }

// ── Accent color provider ──
final accentColorProvider = StateProvider<AppAccentColor>(
  (ref) => AppAccentColor.green,
);

// ── Font size provider (12–20; default 14) ──
final fontSizeProvider = StateProvider<double>((ref) => 14.0);

// ── User memory note (persisted in-memory for now) ──
final userMemoryProvider = StateProvider<String>((ref) => '');

GoRouter _createRouter(Ref ref) {
  return GoRouter(
    navigatorKey: routerKey,
    initialLocation: '/today',
    refreshListenable: _AuthNotifierStream(ref),
    redirect: (context, state) {
      final authStatus = ref.read(authProvider).status;
      final currentLocation = state.matchedLocation;

      // After sign-in or sign-out, redirect to /today
      // - unauthenticated: user just signed out, go to today (clean state)
      // - authenticated but coming from non-app location (e.g., after sign-in)
      if (authStatus == AuthStatus.unauthenticated &&
          currentLocation != '/today') {
        return '/today';
      }

      return null; // no redirect
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/today',
            builder: (context, state) => const TodayScreen(),
            routes: [
              GoRoute(
                path: 'task/:taskId',
                pageBuilder: (context, state) => slideFadeTransition(
                  key: state.pageKey,
                  child: TaskDetailScreen(
                    taskId: state.pathParameters['taskId']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/plans',
            builder: (context, state) => const PlansScreen(),
            routes: [
              GoRoute(
                path: ':planId',
                pageBuilder: (context, state) => slideFadeTransition(
                  key: state.pageKey,
                  child: PlanRoadmapScreen(
                    planId: state.pathParameters['planId']!,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'milestones/:milestoneId',
                    pageBuilder: (context, state) => slideFadeTransition(
                      key: state.pageKey,
                      child: MilestoneInsightScreen(
                        milestoneId: state.pathParameters['milestoneId']!,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/chat',
            builder: (context, state) => const ChatScreen(),
          ),
          GoRoute(
            path: '/memory',
            builder: (context, state) => const MemoryScreen(),
          ),
        ],
      ),
      // History screen (outside shell, accessed from drawer)
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) => _createRouter(ref));

class _AuthNotifierStream extends ChangeNotifier {
  _AuthNotifierStream(Ref ref) {
    ref.listen<AuthStatus>(
      authProvider.select((s) => s.status),
      (_, _) => notifyListeners(),
    );
  }
}

class LifeAgentApp extends ConsumerWidget {
  const LifeAgentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final fontSize = ref.watch(fontSizeProvider);
    final accentColor = ref.watch(accentColorProvider);
    // 14.0 is the base; scale linearly so 14→1.0, 12→0.857, 20→1.428
    final textScaleFactor = fontSize / 14.0;

    return MaterialApp.router(
      title: 'Life Agent',
      theme: AppTheme.getLightTheme(accentColor),
      darkTheme: AppTheme.getDarkTheme(accentColor),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Apply the font scaler inside MaterialApp so it inherits
        // correct screen size/padding while overriding the text scaler.
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        );
      },
    );
  }
}
