import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/features/device_ingestion/data/datasources/device_stats_native_datasource.dart';
import 'package:matrix_ai_os/features/device_ingestion/domain/services/call_log_ingestion_service.dart';
import 'package:matrix_ai_os/features/device_ingestion/domain/services/notification_ingestion_handler.dart';
import 'package:matrix_ai_os/features/device_ingestion/domain/services/usage_ingestion_service.dart';

const String kPeriodicDeviceSyncTask = 'matrix_ai_periodic_sync';
const String kPeriodicSyncUniqueName = 'matrix_periodic_sync_id';

/// Top-level callback dispatcher for Workmanager background execution.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundSyncWorker] Background task started: $task');

    try {
      WidgetsFlutterBinding.ensureInitialized();

      // 1. Initialize encrypted database core
      final dbService = LocalDatabaseService();
      await dbService.initialize();

      // 2. Intercept device metrics
      final dataSource = DeviceStatsNativeDataSource();
      final usageService = UsageIngestionService(dataSource: dataSource, dbService: dbService);
      final callLogService = CallLogIngestionService(dataSource: dataSource, dbService: dbService);
      final notificationHandler = NotificationIngestionHandler(dataSource: dataSource, dbService: dbService);

      // 3. Execute sync passes
      await usageService.syncTodayUsage();
      await callLogService.syncRecentCalls(limit: 30);
      await notificationHandler.drainBufferedNotifications();

      debugPrint('[BackgroundSyncWorker] Background periodic sync completed successfully.');
      return Future.value(true);
    } catch (e, stack) {
      debugPrint('[BackgroundSyncWorker] Background task failed: $e\n$stack');
      return Future.value(false);
    }
  });
}

/// Helper service to manage Workmanager periodic scheduling with battery constraints.
class BackgroundSyncWorker {
  BackgroundSyncWorker._();

  /// Initializes the background workmanager.
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(callbackDispatcher);
      debugPrint('[BackgroundSyncWorker] Workmanager initialized.');
    } catch (e) {
      debugPrint('[BackgroundSyncWorker] Workmanager initialization skipped or failed: $e');
    }
  }

  /// Schedules periodic background syncing every 6 hours with battery-not-low constraints.
  static Future<void> schedulePeriodicSync() async {
    try {
      await Workmanager().registerPeriodicTask(
        kPeriodicSyncUniqueName,
        kPeriodicDeviceSyncTask,
        frequency: const Duration(hours: 6),
        constraints: Constraints(
          requiresBatteryNotLow: true,
          networkType: NetworkType.notRequired,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      debugPrint('[BackgroundSyncWorker] Scheduled 6-hour periodic sync with battery-not-low constraint.');
    } catch (e) {
      debugPrint('[BackgroundSyncWorker] Scheduling failed: $e');
    }
  }

  /// Cancels all scheduled background work tasks.
  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
