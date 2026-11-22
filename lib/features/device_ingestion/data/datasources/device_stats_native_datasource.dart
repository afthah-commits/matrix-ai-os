import 'package:flutter/services.dart';

/// Native datasource interfacing with Android MethodChannels for device telemetry and permissions.
class DeviceStatsNativeDataSource {
  static const MethodChannel _statsChannel = MethodChannel('com.matrixai.os/device_stats');
  static const MethodChannel _notificationChannel = MethodChannel('com.matrixai.os/notifications');

  void Function(Map<String, dynamic> notification)? _notificationCallback;

  DeviceStatsNativeDataSource() {
    _notificationChannel.setMethodCallHandler(_handleNativeNotificationCall);
  }

  Future<dynamic> _handleNativeNotificationCall(MethodCall call) async {
    if (call.method == 'onNotificationReceived') {
      final arguments = call.arguments;
      if (arguments is Map) {
        final casted = Map<String, dynamic>.from(arguments);
        _notificationCallback?.call(casted);
      }
    }
  }

  /// Registers an active handler for incoming push notifications.
  void setNotificationListener(void Function(Map<String, dynamic> notification) listener) {
    _notificationCallback = listener;
  }

  /// Fetches daily screen time and per-app usage from Android UsageStatsManager.
  Future<Map<String, dynamic>> getDailyAppUsage() async {
    final result = await _statsChannel.invokeMethod<Map<dynamic, dynamic>>('getDailyAppUsage');
    if (result == null) return {};
    return Map<String, dynamic>.from(result);
  }

  /// Fetches recent call logs from CallLog.Calls.
  Future<List<Map<String, dynamic>>> getRecentCallLogs({
    int limit = 50,
    int? sinceTimestamp,
  }) async {
    final result = await _statsChannel.invokeListMethod<dynamic>(
      'getRecentCallLogs',
      {
        'limit': limit,
        'sinceTimestamp': ?sinceTimestamp,
      },
    );

    if (result == null) return [];
    return result
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Checks whether special Android permissions (UsageStats, NotificationListener, CallLog) are granted.
  Future<Map<String, bool>> checkPermissions() async {
    final result = await _statsChannel.invokeMethod<Map<dynamic, dynamic>>('checkPermissions');
    if (result == null) {
      return {
        'usageStatsGranted': false,
        'notificationListenerGranted': false,
        'callLogGranted': false,
      };
    }
    return {
      'usageStatsGranted': result['usageStatsGranted'] as bool? ?? false,
      'notificationListenerGranted': result['notificationListenerGranted'] as bool? ?? false,
      'callLogGranted': result['callLogGranted'] as bool? ?? false,
    };
  }

  /// Drains any transaction/alert notifications that arrived while Flutter was detached.
  Future<List<Map<String, dynamic>>> getBufferedNotifications() async {
    final result = await _statsChannel.invokeListMethod<dynamic>('getBufferedNotifications');
    if (result == null) return [];
    return result
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Opens Android Settings > Usage Access.
  Future<bool> openUsageAccessSettings() async {
    final res = await _statsChannel.invokeMethod<bool>('openUsageAccessSettings');
    return res ?? false;
  }

  /// Opens Android Settings > Notification Access.
  Future<bool> openNotificationListenerSettings() async {
    final res = await _statsChannel.invokeMethod<bool>('openNotificationListenerSettings');
    return res ?? false;
  }

  /// Opens Android Settings > Application Details.
  Future<bool> openAppSettings() async {
    final res = await _statsChannel.invokeMethod<bool>('openAppSettings');
    return res ?? false;
  }
}
