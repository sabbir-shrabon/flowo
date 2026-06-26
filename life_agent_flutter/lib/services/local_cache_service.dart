import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/daily_schedule_models.dart';
import '../models/plan_models.dart';
import '../models/task_models.dart';

class LocalCacheService {
  static final LocalCacheService _instance = LocalCacheService._internal();
  factory LocalCacheService() => _instance;
  LocalCacheService._internal();

  static LocalCacheService get instance => _instance;

  static const String _plansBoxName = 'plans_box';
  static const String _dailyScheduleBoxName = 'daily_schedule_cache';
  static const String _taskDetailsBoxName = 'task_details_box';
  static const String _pendingSyncsBoxName = 'pending_syncs_box';
  static const String _settingsBoxName = 'app_settings_box';

  // Settings keys
  static const String kThemeMode = 'themeMode';
  static const String kAccentColor = 'accentColor';
  static const String kFontSize = 'fontSize';
  static const String kUserMemory = 'userMemory';

  late Box<String> _plansBox;
  late Box<String> _dailyScheduleBox;
  late Box<String> _taskDetailsBox;
  late Box<String> _pendingSyncsBox;
  late Box<String> _settingsBox;

  Future<void> init() async {
    _plansBox = await Hive.openBox<String>(_plansBoxName);
    _dailyScheduleBox = await Hive.openBox<String>(_dailyScheduleBoxName);
    _taskDetailsBox = await Hive.openBox<String>(_taskDetailsBoxName);
    _pendingSyncsBox = await Hive.openBox<String>(_pendingSyncsBoxName);
    _settingsBox = await Hive.openBox<String>(_settingsBoxName);
    debugPrint('[CacheLayer] LocalCacheService initialized');
  }

  Future<void> dispose() async {
    await _plansBox.close();
    await _dailyScheduleBox.close();
    await _taskDetailsBox.close();
    await _pendingSyncsBox.close();
    await _settingsBox.close();
    debugPrint('[CacheLayer] LocalCacheService disposed');
  }

  // ── App Settings ────────────────────────────────────────────────────────────

  /// Saves an app setting. Value must be a String (serialize before calling).
  Future<void> saveSetting(String key, String value) async {
    try {
      await _settingsBox.put(key, value);
    } catch (e) {
      debugPrint('[CacheLayer] Error saving setting "$key": $e');
    }
  }

  /// Reads a persisted app setting. Returns null if not yet set.
  String? getSetting(String key) {
    try {
      return _settingsBox.get(key);
    } catch (e) {
      debugPrint('[CacheLayer] Error reading setting "$key": $e');
      return null;
    }
  }

  /// Clears only the personal / account-bound settings (user memory note).
  /// Device settings (theme, accent color, font size) are intentionally kept.
  Future<void> clearPersonalSettings() async {
    try {
      await _settingsBox.delete(kUserMemory);
      debugPrint('[CacheLayer] Cleared personal settings (userMemory)');
    } catch (e) {
      debugPrint('[CacheLayer] Error clearing personal settings: $e');
    }
  }

  // ── Daily Schedule Cache ───────────────────────────────────────────────────

  Future<void> saveDailySchedule(String userId, DailySchedule schedule) async {
    final startTime = DateTime.now();
    try {
      await _dailyScheduleBox.clear();
      await _dailyScheduleBox.put(userId, jsonEncode(schedule.toJson()));
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint(
        '[CacheLayer] Saved daily schedule for user $userId in ${duration}ms',
      );
    } catch (e) {
      debugPrint('[CacheLayer] Error saving daily schedule: $e');
    }
  }

  DailySchedule? getCachedDailySchedule(String userId) {
    final startTime = DateTime.now();
    try {
      final jsonString = _dailyScheduleBox.get(userId);
      if (jsonString == null) return null;
      final schedule = DailySchedule.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonString) as Map),
      );
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint(
        '[CacheLayer] Read cached daily schedule for user $userId in ${duration}ms',
      );
      return schedule;
    } catch (e) {
      debugPrint('[CacheLayer] Error reading daily schedule: $e');
      return null;
    }
  }

  /// Evicts the cached daily schedule for [userId].
  /// Call this before a hard/manual refresh so [getCachedDailySchedule]
  /// returns null and the UI enters a real loading state.
  void clearDailySchedule(String userId) {
    try {
      _dailyScheduleBox.delete(userId);
      debugPrint('[CacheLayer] Cleared daily schedule for user $userId');
    } catch (e) {
      debugPrint('[CacheLayer] Error clearing daily schedule: $e');
    }
  }

  // ── Plans Cache ─────────────────────────────────────────────────────────────

  Future<void> savePlans(String userId, List<PlanDetailResponse> plans) async {
    final startTime = DateTime.now();
    try {
      final jsonString = jsonEncode(plans.map((p) => p.toJson()).toList());
      await _plansBox.put(userId, jsonString);
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint(
        '[CacheLayer] Saved ${plans.length} plans for user $userId in ${duration}ms',
      );
    } catch (e) {
      debugPrint('[CacheLayer] Error saving plans: $e');
    }
  }

  List<PlanDetailResponse>? getCachedPlans(String userId) {
    final startTime = DateTime.now();
    try {
      final jsonString = _plansBox.get(userId);
      if (jsonString == null) return null;
      final List<dynamic> list = jsonDecode(jsonString);
      final plans = list
          .map((item) => PlanDetailResponse.fromJson(item))
          .toList();
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint(
        '[CacheLayer] Read ${plans.length} cached plans for user $userId in ${duration}ms',
      );
      return plans;
    } catch (e) {
      debugPrint('[CacheLayer] Error reading cached plans: $e');
      return null;
    }
  }

  Future<void> clearPlans(String userId) async {
    await _plansBox.delete(userId);
    await _plansBox.delete('${userId}_all');
    debugPrint('[CacheLayer] Cleared plans for user $userId');
  }

  // ── All Plans Cache (simple PlanResponse list) ─────────────────────────────

  Future<void> saveAllPlans(String userId, List<PlanResponse> plans) async {
    final startTime = DateTime.now();
    try {
      final jsonString = jsonEncode(plans.map((p) => p.toJson()).toList());
      await _plansBox.put('${userId}_all', jsonString);
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint(
        '[CacheLayer] Saved ${plans.length} all-plans for user $userId in ${duration}ms',
      );
    } catch (e) {
      debugPrint('[CacheLayer] Error saving all plans: $e');
    }
  }

  List<PlanResponse>? getCachedAllPlans(String userId) {
    final startTime = DateTime.now();
    try {
      final jsonString = _plansBox.get('${userId}_all');
      if (jsonString == null) return null;
      final List<dynamic> list = jsonDecode(jsonString);
      final plans = list.map((item) => PlanResponse.fromJson(item)).toList();
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint(
        '[CacheLayer] Read ${plans.length} cached all-plans for user $userId in ${duration}ms',
      );
      return plans;
    } catch (e) {
      debugPrint('[CacheLayer] Error reading cached all plans: $e');
      return null;
    }
  }

  // ── Task Detail Cache ───────────────────────────────────────────────────────

  Future<void> saveTaskDetail(String taskId, TaskDetailResponse detail) async {
    final startTime = DateTime.now();
    try {
      final jsonString = jsonEncode(detail.toJson());
      await _taskDetailsBox.put(taskId, jsonString);
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[CacheLayer] Saved detail for task $taskId in ${duration}ms');
    } catch (e) {
      debugPrint('[CacheLayer] Error saving task detail: $e');
    }
  }

  TaskDetailResponse? getCachedTaskDetail(String taskId) {
    final startTime = DateTime.now();
    try {
      final jsonString = _taskDetailsBox.get(taskId);
      if (jsonString == null) return null;
      final detail = TaskDetailResponse.fromJson(jsonDecode(jsonString));
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint(
        '[CacheLayer] Read cached detail for task $taskId in ${duration}ms',
      );
      return detail;
    } catch (e) {
      debugPrint('[CacheLayer] Error reading task detail: $e');
      return null;
    }
  }

  // ── Pending Sync Queue ──────────────────────────────────────────────────────

  Future<void> enqueuePendingSync(
    String type,
    Map<String, dynamic> payload,
  ) async {
    final startTime = DateTime.now();
    try {
      final entry = {
        'type': type,
        'payload': payload,
        'created_at': DateTime.now().toIso8601String(),
      };
      await _pendingSyncsBox.add(jsonEncode(entry));
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[CacheLayer] Enqueued pending sync ($type) in ${duration}ms');
    } catch (e) {
      debugPrint('[CacheLayer] Error enqueueing pending sync: $e');
    }
  }

  List<Map<String, dynamic>> getPendingSyncs() {
    final startTime = DateTime.now();
    try {
      final results = <Map<String, dynamic>>[];
      for (var key in _pendingSyncsBox.keys) {
        final jsonString = _pendingSyncsBox.get(key);
        if (jsonString != null) {
          final Map<String, dynamic> data = jsonDecode(jsonString);
          data['hive_key'] = key;
          results.add(data);
        }
      }
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint(
        '[CacheLayer] Read ${results.length} pending syncs in ${duration}ms',
      );

      // Sort by created_at ascending
      results.sort((a, b) {
        final dateA =
            DateTime.tryParse(a['created_at'] as String? ?? '') ??
            DateTime.now();
        final dateB =
            DateTime.tryParse(b['created_at'] as String? ?? '') ??
            DateTime.now();
        return dateA.compareTo(dateB);
      });
      return results;
    } catch (e) {
      debugPrint('[CacheLayer] Error reading pending syncs: $e');
      return [];
    }
  }

  Future<void> removePendingSync(dynamic key) async {
    try {
      await _pendingSyncsBox.delete(key);
      debugPrint('[CacheLayer] Removed pending sync $key');
    } catch (e) {
      debugPrint('[CacheLayer] Error removing pending sync: $e');
    }
  }

  // ── Clear All Cache (for sign-out) ───────────────────────────────────────────

  /// Clears all cached data. Call this on sign-out to ensure
  /// a fresh state for the next user (or same user re-authenticating).
  Future<void> clearAll() async {
    final startTime = DateTime.now();
    try {
      await _dailyScheduleBox.clear();
      await _plansBox.clear();
      await _taskDetailsBox.clear();
      await _pendingSyncsBox.clear();
      // Also clear personal account-bound settings (not device settings)
      await clearPersonalSettings();
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[CacheLayer] Cleared all cache in ${duration}ms');
    } catch (e) {
      debugPrint('[CacheLayer] Error clearing all cache: $e');
    }
  }
}
