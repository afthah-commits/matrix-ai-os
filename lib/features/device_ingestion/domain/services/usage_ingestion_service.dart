import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/core/utils/formatters.dart';
import 'package:matrix_ai_os/features/device_ingestion/data/datasources/device_stats_native_datasource.dart';
import 'package:matrix_ai_os/features/device_ingestion/domain/models/app_usage_model.dart';
import 'package:matrix_ai_os/objectbox.g.dart';

/// Ingests on-device screen time telemetry and stores it as an encrypted MemoryNode.
class UsageIngestionService {
  final DeviceStatsNativeDataSource _dataSource;
  final LocalDatabaseService _dbService;

  UsageIngestionService({
    required DeviceStatsNativeDataSource dataSource,
    required LocalDatabaseService dbService,
  })  : _dataSource = dataSource,
        _dbService = dbService;

  /// Fetches daily app usage from Android UsageStatsManager, formats summary,
  /// and updates or inserts today's encrypted MemoryNode.
  Future<DailyUsageSummary?> syncTodayUsage() async {
    try {
      final rawData = await _dataSource.getDailyAppUsage();
      if (rawData.isEmpty) return null;

      final summary = DailyUsageSummary.fromMap(rawData);
      final todayStr = Formatters.formatIsoDay(DateTime.now());

      // Format clean summary description
      final buffer = StringBuffer()
        ..write('Screen Time: ${summary.totalScreenTimeMinutes}m today');

      if (summary.apps.isNotEmpty) {
        final topApps = summary.apps.take(4).map((a) => '${a.appName} (${a.minutes}m)').join(', ');
        buffer.write('. Top apps: $topApps');
      }

      final content = buffer.toString();
      final metadataJson = jsonEncode({
        'date': todayStr,
        'minutes': summary.totalScreenTimeMinutes,
        'startTime': summary.startTime,
        'endTime': summary.endTime,
        'apps': summary.apps.take(8).map((a) => a.toMap()).toList(),
      });

      // Avoid duplicate screen_time entries for the same day:
      // Query if an existing screen_time node exists for today
      final now = DateTime.now();
      final midnightToday = DateTime(now.year, now.month, now.day);
      final memoryBox = _dbService.memoryBox;

      final existingQuery = (memoryBox.query(
        MemoryNode_.category.equals(MemoryCategory.screenTime)
            .and(MemoryNode_.timestamp.greaterOrEqual(midnightToday.millisecondsSinceEpoch)),
      )).build();

      final existingList = existingQuery.find();
      existingQuery.close();

      if (existingList.isNotEmpty) {
        // Update existing node with fresh encrypted telemetry
        final node = existingList.first;
        final encryptedContent = await _dbService.cipherService.encrypt(content);
        final encryptedMetadata = await _dbService.cipherService.encrypt(metadataJson);

        node.content = encryptedContent;
        node.metadataJson = encryptedMetadata;
        node.timestamp = now;
        memoryBox.put(node);
        debugPrint('[UsageIngestionService] Updated existing screen_time node #${node.id} for $todayStr.');
      } else {
        // Insert new encrypted node
        final node = await _dbService.insertMemoryNode(
          category: MemoryCategory.screenTime,
          content: content,
          metadataJson: metadataJson,
          timestamp: now,
        );
        debugPrint('[UsageIngestionService] Inserted new encrypted screen_time node #${node.id} (${summary.totalScreenTimeMinutes} mins).');
      }

      return summary;
    } catch (e) {
      debugPrint('[UsageIngestionService] Failed to sync usage stats: $e');
      return null;
    }
  }
}
