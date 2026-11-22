import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:matrix_ai_os/core/database/database_providers.dart';
import 'package:matrix_ai_os/features/device_ingestion/data/datasources/device_stats_native_datasource.dart';
import 'package:matrix_ai_os/features/device_ingestion/domain/services/call_log_ingestion_service.dart';
import 'package:matrix_ai_os/features/device_ingestion/domain/services/notification_ingestion_handler.dart';
import 'package:matrix_ai_os/features/device_ingestion/domain/services/usage_ingestion_service.dart';

final deviceStatsDataSourceProvider = Provider<DeviceStatsNativeDataSource>((ref) {
  return DeviceStatsNativeDataSource();
});

final usageIngestionServiceProvider = Provider<UsageIngestionService>((ref) {
  final dataSource = ref.watch(deviceStatsDataSourceProvider);
  final dbService = ref.watch(localDatabaseServiceProvider);
  return UsageIngestionService(dataSource: dataSource, dbService: dbService);
});

final callLogIngestionServiceProvider = Provider<CallLogIngestionService>((ref) {
  final dataSource = ref.watch(deviceStatsDataSourceProvider);
  final dbService = ref.watch(localDatabaseServiceProvider);
  return CallLogIngestionService(dataSource: dataSource, dbService: dbService);
});

final notificationIngestionHandlerProvider = Provider<NotificationIngestionHandler>((ref) {
  final dataSource = ref.watch(deviceStatsDataSourceProvider);
  final dbService = ref.watch(localDatabaseServiceProvider);
  return NotificationIngestionHandler(dataSource: dataSource, dbService: dbService);
});

class DevicePermissionsState {
  final bool usageStatsGranted;
  final bool notificationListenerGranted;
  final bool callLogGranted;
  final bool galleryPermissionGranted;
  final bool isSyncing;
  final String? lastSyncResult;

  const DevicePermissionsState({
    this.usageStatsGranted = false,
    this.notificationListenerGranted = false,
    this.callLogGranted = false,
    this.galleryPermissionGranted = false,
    this.isSyncing = false,
    this.lastSyncResult,
  });

  DevicePermissionsState copyWith({
    bool? usageStatsGranted,
    bool? notificationListenerGranted,
    bool? callLogGranted,
    bool? galleryPermissionGranted,
    bool? isSyncing,
    String? lastSyncResult,
  }) {
    return DevicePermissionsState(
      usageStatsGranted: usageStatsGranted ?? this.usageStatsGranted,
      notificationListenerGranted: notificationListenerGranted ?? this.notificationListenerGranted,
      callLogGranted: callLogGranted ?? this.callLogGranted,
      galleryPermissionGranted: galleryPermissionGranted ?? this.galleryPermissionGranted,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncResult: lastSyncResult ?? this.lastSyncResult,
    );
  }
}

class DeviceIngestionController extends StateNotifier<DevicePermissionsState> {
  final DeviceStatsNativeDataSource _dataSource;
  final UsageIngestionService _usageService;
  final CallLogIngestionService _callLogService;
  final NotificationIngestionHandler _notifHandler;

  DeviceIngestionController({
    required DeviceStatsNativeDataSource dataSource,
    required UsageIngestionService usageService,
    required CallLogIngestionService callLogService,
    required NotificationIngestionHandler notifHandler,
  })  : _dataSource = dataSource,
        _usageService = usageService,
        _callLogService = callLogService,
        _notifHandler = notifHandler,
        super(const DevicePermissionsState());

  /// Checks live permission status for Usage Stats, Notification Listener, Call Logs, and Gallery.
  Future<void> checkPermissions() async {
    try {
      final perms = await _dataSource.checkPermissions();
      bool galleryGranted = false;
      try {
        final pmState = await PhotoManager.requestPermissionExtend();
        galleryGranted = pmState.hasAccess;
      } catch (_) {}

      state = state.copyWith(
        usageStatsGranted: perms['usageStatsGranted'] ?? false,
        notificationListenerGranted: perms['notificationListenerGranted'] ?? false,
        callLogGranted: perms['callLogGranted'] ?? false,
        galleryPermissionGranted: galleryGranted,
      );
    } catch (_) {}
  }

  /// Requests Call Log permission via permission_handler.
  Future<void> requestCallLogPermission() async {
    final status = await Permission.phone.request();
    state = state.copyWith(callLogGranted: status.isGranted);
  }

  /// Requests Gallery/Photo access permission via photo_manager.
  Future<void> requestGalleryPermission() async {
    try {
      final res = await PhotoManager.requestPermissionExtend();
      state = state.copyWith(galleryPermissionGranted: res.hasAccess);
    } catch (_) {}
  }

  /// Opens Android Settings for Usage Access.
  Future<void> openUsageAccessSettings() async {
    await _dataSource.openUsageAccessSettings();
  }

  /// Opens Android Settings for Notification Listener.
  Future<void> openNotificationListenerSettings() async {
    await _dataSource.openNotificationListenerSettings();
  }

  /// Triggers a full manual ingestion pass across Usage Stats, Call Logs, and Notifications.
  Future<Map<String, dynamic>> syncAllDeviceData() async {
    state = state.copyWith(isSyncing: true, lastSyncResult: null);
    try {
      final usageSummary = await _usageService.syncTodayUsage();
      final callsCount = await _callLogService.syncRecentCalls(limit: 50);
      final notifCount = await _notifHandler.drainBufferedNotifications();

      final summaryMessage =
          'Sync Complete: ${usageSummary != null ? "${usageSummary.totalScreenTimeMinutes}m usage, " : ""}$callsCount calls, $notifCount transactions/alerts';

      state = state.copyWith(
        isSyncing: false,
        lastSyncResult: summaryMessage,
      );

      return {
        'screenTimeMinutes': usageSummary?.totalScreenTimeMinutes ?? 0,
        'newCallsCount': callsCount,
        'newNotificationsCount': notifCount,
      };
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        lastSyncResult: 'Sync error: $e',
      );
      return {};
    }
  }
}

final deviceIngestionControllerProvider =
    StateNotifierProvider<DeviceIngestionController, DevicePermissionsState>((ref) {
  final dataSource = ref.watch(deviceStatsDataSourceProvider);
  final usageService = ref.watch(usageIngestionServiceProvider);
  final callLogService = ref.watch(callLogIngestionServiceProvider);
  final notifHandler = ref.watch(notificationIngestionHandlerProvider);

  final controller = DeviceIngestionController(
    dataSource: dataSource,
    usageService: usageService,
    callLogService: callLogService,
    notifHandler: notifHandler,
  );
  controller.checkPermissions();
  return controller;
});
