/// Information about screen time for a specific application.
class AppUsageInfo {
  final String packageName;
  final String appName;
  final int minutes;
  final int lastTimeUsed;

  const AppUsageInfo({
    required this.packageName,
    required this.appName,
    required this.minutes,
    required this.lastTimeUsed,
  });

  factory AppUsageInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppUsageInfo(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? '',
      minutes: (map['minutes'] as num?)?.toInt() ?? 0,
      lastTimeUsed: (map['lastTimeUsed'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'packageName': packageName,
      'appName': appName,
      'minutes': minutes,
      'lastTimeUsed': lastTimeUsed,
    };
  }
}

/// Aggregated daily usage summary across all device applications.
class DailyUsageSummary {
  final int totalScreenTimeMinutes;
  final int startTime;
  final int endTime;
  final List<AppUsageInfo> apps;

  const DailyUsageSummary({
    required this.totalScreenTimeMinutes,
    required this.startTime,
    required this.endTime,
    required this.apps,
  });

  factory DailyUsageSummary.fromMap(Map<dynamic, dynamic> map) {
    final rawApps = (map['apps'] as List<dynamic>?) ?? [];
    final appList = rawApps
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => AppUsageInfo.fromMap(m))
        .toList();

    return DailyUsageSummary(
      totalScreenTimeMinutes: (map['totalScreenTimeMinutes'] as num?)?.toInt() ?? 0,
      startTime: (map['startTime'] as num?)?.toInt() ?? 0,
      endTime: (map['endTime'] as num?)?.toInt() ?? 0,
      apps: appList,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalScreenTimeMinutes': totalScreenTimeMinutes,
      'startTime': startTime,
      'endTime': endTime,
      'apps': apps.map((a) => a.toMap()).toList(),
    };
  }
}
