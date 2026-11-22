import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/features/device_ingestion/data/datasources/device_stats_native_datasource.dart';
import 'package:matrix_ai_os/features/device_ingestion/domain/models/call_log_model.dart';
import 'package:matrix_ai_os/objectbox.g.dart';

/// Service responsible for querying and storing encrypted telephony call logs.
class CallLogIngestionService {
  final DeviceStatsNativeDataSource _dataSource;
  final LocalDatabaseService _dbService;

  CallLogIngestionService({
    required DeviceStatsNativeDataSource dataSource,
    required LocalDatabaseService dbService,
  })  : _dataSource = dataSource,
        _dbService = dbService;

  /// Fetches recent call logs and persists un-indexed calls as encrypted MemoryNodes.
  Future<int> syncRecentCalls({int limit = 50}) async {
    try {
      final rawLogs = await _dataSource.getRecentCallLogs(limit: limit);
      if (rawLogs.isEmpty) return 0;

      final callEntries = rawLogs.map((m) => CallLogEntry.fromMap(m)).toList();
      final memoryBox = _dbService.memoryBox;

      // Query recent call_log nodes to prevent duplicate inserts
      final oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));
      final existingQuery = (memoryBox.query(
        MemoryNode_.category.equals(MemoryCategory.callLog)
            .and(MemoryNode_.timestamp.greaterOrEqual(oneWeekAgo.millisecondsSinceEpoch)),
      )).build();

      final existingNodes = existingQuery.find();
      existingQuery.close();

      // Collect existing timestamps to avoid re-adding
      final existingTimestamps = existingNodes.map((n) => n.timestamp.millisecondsSinceEpoch).toSet();

      int newlyIngested = 0;
      for (final call in callEntries) {
        final callEpoch = call.timestamp.millisecondsSinceEpoch;
        if (existingTimestamps.contains(callEpoch)) {
          // Already ingested
          continue;
        }

        final content = 'Call [${call.type}]: ${call.contactName} (${call.formattedDuration})';
        final metadataJson = jsonEncode(call.toMap());

        await _dbService.insertMemoryNode(
          category: MemoryCategory.callLog,
          content: content,
          metadataJson: metadataJson,
          timestamp: call.timestamp,
        );

        existingTimestamps.add(callEpoch);
        newlyIngested++;
      }

      debugPrint('[CallLogIngestionService] Ingested $newlyIngested new call logs.');
      return newlyIngested;
    } catch (e) {
      debugPrint('[CallLogIngestionService] Failed to sync call logs: $e');
      return 0;
    }
  }
}
