import 'package:flutter/foundation.dart';
import 'local_cache_service.dart';
import 'connectivity_service.dart';
import 'adaptive_service.dart';
import '../models/task_models.dart';
import '../models/plan_models.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final LocalCacheService _cache = LocalCacheService.instance;
  final ConnectivityService _connectivity = ConnectivityService();

  Future<void> syncPendingTasks() async {
    if (!await _connectivity.hasInternet()) {
      debugPrint('[CacheLayer] Sync skipped: no internet');
      return;
    }

    final pendings = _cache.getPendingSyncs();
    if (pendings.isEmpty) {
      debugPrint('[CacheLayer] No pending tasks to sync');
      return;
    }

    debugPrint('[CacheLayer] Starting sync of ${pendings.length} tasks');

    for (var pending in pendings) {
      try {
        final type = pending['type'] as String;
        final payloadData = Map<String, dynamic>.from(pending['payload']);
        
        if (type == 'task_update') {
          // Construct TaskUpdatePayload from map
          final payload = TaskUpdatePayload(
            taskId: payloadData['task_id'],
            status: TaskStatus.values.firstWhere(
              (e) => e.name == payloadData['status'],
              orElse: () => TaskStatus.pending,
            ),
            feedbackText: payloadData['feedback_text'],
          );

          debugPrint('[CacheLayer] Syncing task ${payload.taskId} status: ${payload.status.name}');
          await updateTask(payload);
        }
        
        // Remove from cache after successful sync
        await _cache.removePendingSync(pending['hive_key']);
      } catch (e) {
        debugPrint('[CacheLayer] Failed to sync pending item: $e');
        // We leave it in the queue to try again later
      }
    }
    
    debugPrint('[CacheLayer] Sync completed');
  }

  Future<void> refreshPlansFromBackend(String userId) async {
    if (!await _connectivity.hasInternet()) return;
    
    final startTime = DateTime.now();
    try {
      debugPrint('[CacheLayer] Fetching fresh plans from backend...');
      final activePlans = await listActivePlans();
      
      // Fetch details sequentially as in TodayScreen
      List<PlanDetailResponse> planDetails = [];
      for (final p in activePlans) {
        planDetails.add(await getPlanDetail(p.id));
      }
      
      // Save all to cache
      await _cache.savePlans(userId, planDetails);
      
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[CacheLayer] Refreshed plans from backend and cached in ${duration}ms');
    } catch (e) {
      debugPrint('[CacheLayer] Error refreshing plans from backend: $e');
    }
  }
}
