import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'widgets/animations.dart';
import 'providers/auth_provider.dart';
import 'models/task_models.dart';
import 'screens/main_shell.dart';
import 'screens/today/today_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/memory/memory_screen.dart';
import 'screens/plans/plans_screen.dart';
import 'screens/plans/plan_roadmap_screen.dart';
import 'screens/plans/milestone_insight_screen.dart';
import 'screens/task_detail/task_detail_screen.dart';
import 'screens/task_workspace/task_workspace_screen.dart';
import 'screens/history/history_screen.dart';
import 'theme/app_theme.dart';
import 'services/local_cache_service.dart';

/// GlobalKey for the root navigator — used by GoRouter.
final GlobalKey<NavigatorState> routerKey = GlobalKey<NavigatorState>();

// ── Helpers to read persisted settings at provider init time ──────────────────

ThemeMode _loadThemeMode() {
  final v = LocalCacheService.instance.getSetting(LocalCacheService.kThemeMode);
  if (v == 'dark') return ThemeMode.dark;
  if (v == 'light') return ThemeMode.light;
  return ThemeMode.light; // default
}

AppAccentColor _loadAccentColor() {
  final v = LocalCacheService.instance.getSetting(LocalCacheService.kAccentColor);
  for (final c in AppAccentColor.values) {
    if (c.name == v) return c;
  }
  return AppAccentColor.green; // default
}

double _loadFontSize() {
  final v = LocalCacheService.instance.getSetting(LocalCacheService.kFontSize);
  if (v != null) return double.tryParse(v) ?? 14.0;
  return 14.0; // default
}

String _loadUserMemory() {
  return LocalCacheService.instance.getSetting(LocalCacheService.kUserMemory) ?? '';
}

// ── Theme mode provider ──
final themeModeProvider = StateProvider<ThemeMode>((ref) => _loadThemeMode());

enum AppAccentColor { green, blue, ash }

// ── Accent color provider ──
final accentColorProvider = StateProvider<AppAccentColor>(
  (ref) => _loadAccentColor(),
);

// ── Font size provider (12–20; default 14) ──
final fontSizeProvider = StateProvider<double>((ref) => _loadFontSize());

// ── User memory note ──
final userMemoryProvider = StateProvider<String>((ref) => _loadUserMemory());

GoRouter _createRouter(Ref ref) {
  return GoRouter(
    navigatorKey: routerKey,
    initialLocation: '/today',
    refreshListenable: _AuthNotifierStream(ref),
    redirect: (context, state) {
      // Navigation is available while signed out. Individual screens and API
      // calls handle authentication-required actions instead of silently
      // sending the user back to Today.
      return null;
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
          GoRoute(
            path: '/task-workspace',
            pageBuilder: (context, state) {
              final extra = state.extra as Map<String, dynamic>;
              return slideFadeTransition(
                key: state.pageKey,
                child: TaskWorkspaceScreen(
                  task: extra['task'] as TaskResponse,
                  planTitle: extra['planTitle'] as String?,
                  milestoneTitle: extra['milestoneTitle'] as String?,
                ),
              );
            },
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

    // ── Persist settings whenever they change ──────────────────────────────
    ref.listen<ThemeMode>(themeModeProvider, (_, next) {
      LocalCacheService.instance.saveSetting(
        LocalCacheService.kThemeMode,
        next == ThemeMode.dark ? 'dark' : 'light',
      );
    });
    ref.listen<AppAccentColor>(accentColorProvider, (_, next) {
      LocalCacheService.instance.saveSetting(
        LocalCacheService.kAccentColor,
        next.name,
      );
    });
    ref.listen<double>(fontSizeProvider, (_, next) {
      LocalCacheService.instance.saveSetting(
        LocalCacheService.kFontSize,
        next.toString(),
      );
    });
    ref.listen<String>(userMemoryProvider, (_, next) {
      LocalCacheService.instance.saveSetting(
        LocalCacheService.kUserMemory,
        next,
      );
    });
    // ──────────────────────────────────────────────────────────────────────

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
