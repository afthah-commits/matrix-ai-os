import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/core/database/models/daily_summary.dart';
import 'package:matrix_ai_os/core/database/models/memory_node.dart';
import 'package:matrix_ai_os/core/utils/formatters.dart';
import 'package:matrix_ai_os/objectbox.g.dart';

/// Summary report returned after a storage pruning cycle finishes.
class PruneReport {
  final int prunedNodeCount;
  final int summariesProcessed;
  final List<String> affectedDates;
  final DateTime executedAt;

  const PruneReport({
    required this.prunedNodeCount,
    required this.summariesProcessed,
    required this.affectedDates,
    required this.executedAt,
  });

  @override
  String toString() {
    return 'PruneReport(pruned: $prunedNodeCount, summaries: $summariesProcessed, dates: ${affectedDates.length})';
  }
}

/// Rolling data retention & auto-pruning service.
///
/// Prevents local storage bloat on low-storage mobile devices (<30MB APK target)
/// by summarizing and purging raw atomic logs older than 30 days while preserving:
/// 1. High-level temporal knowledge via [DailySummary]
/// 2. Permanent knowledge documents ([MemoryCategory.ocrDoc])
/// 3. Explicitly pinned memories ([MemoryNode.isPinned] == true)
class StoragePrunerService {
  final LocalDatabaseService _dbService;

  StoragePrunerService({required LocalDatabaseService dbService})
      : _dbService = dbService;

  /// Executes a pruning pass over expired raw memory nodes.
  ///
  /// [customRetentionDays]: Optional override for retention days (defaults to 30).
  Future<PruneReport> pruneExpiredLogs({int? customRetentionDays}) async {
    final retentionDays = customRetentionDays ?? AppConstants.retentionPeriodDays;
    final now = DateTime.now();
    final cutoffDateTime = now.subtract(Duration(days: retentionDays));

    final memoryBox = _dbService.memoryBox;
    final summaryBox = _dbService.summaryBox;

    // 1. Query nodes older than cutoff and not pinned
    final query = (memoryBox.query(
      MemoryNode_.timestamp.lessThan(cutoffDateTime.millisecondsSinceEpoch)
          .and(MemoryNode_.isPinned.equals(false)),
    )).build();

    final expiredNodes = query.find();
    query.close();

    // 2. Filter out immune categories (such as OCR documents and indexed receipts)
    final nodesToPrune = expiredNodes.where((node) {
      return !MemoryCategory.immuneFromPruning.contains(node.category);
    }).toList();

    if (nodesToPrune.isEmpty) {
      debugPrint('[StoragePrunerService] No expired memory nodes to prune (cutoff: $cutoffDateTime).');
      return PruneReport(
        prunedNodeCount: 0,
        summariesProcessed: 0,
        affectedDates: const [],
        executedAt: now,
      );
    }

    debugPrint('[StoragePrunerService] Found ${nodesToPrune.length} candidate memory nodes for auto-pruning.');

    // 3. Group nodes by day (ISO 'yyyy-MM-dd')
    final Map<String, List<MemoryNode>> nodesByDay = {};
    for (final node in nodesToPrune) {
      final dayKey = Formatters.formatIsoDay(node.timestamp);
      nodesByDay.putIfAbsent(dayKey, () => []).add(node);
    }

    final affectedDates = <String>[];

    // 4. Summarize each day into DailySummary
    for (final entry in nodesByDay.entries) {
      final dayKey = entry.key;
      final dayNodes = entry.value;

      int screenTimeMinutes = 0;
      double totalSpent = 0.0;
      final categoryCounts = <String, int>{};
      final sampleSnippets = <String>[];

      for (final node in dayNodes) {
        categoryCounts[node.category] = (categoryCounts[node.category] ?? 0) + 1;

        // Decrypt payload to aggregate data
        try {
          final decrypted = await _dbService.decryptNode(node);

          if (node.category == MemoryCategory.screenTime) {
            screenTimeMinutes += _parseMinutes(decrypted.content, decrypted.metadataJson);
          } else if (node.category == MemoryCategory.transaction) {
            totalSpent += _parseSpent(decrypted.content, decrypted.metadataJson);
          }

          if (sampleSnippets.length < 5 && decrypted.content.isNotEmpty) {
            final truncated = decrypted.content.length > 50
                ? '${decrypted.content.substring(0, 50)}...'
                : decrypted.content;
            sampleSnippets.add('[${node.category}] $truncated');
          }
        } catch (e) {
          debugPrint('[StoragePrunerService] Failed decrypting node ${node.id} during pruning: $e');
        }
      }

      final summaryDescription = StringBuffer()
        ..write('Archived ${dayNodes.length} events: ')
        ..write(categoryCounts.entries.map((e) => '${e.value} ${e.key}').join(', '));

      if (screenTimeMinutes > 0) {
        summaryDescription.write(' | Screen Time: ${screenTimeMinutes}m');
      }
      if (totalSpent > 0.0) {
        summaryDescription.write(' | Spend: \$${totalSpent.toStringAsFixed(2)}');
      }

      // Check if DailySummary already exists for this day
      final existingQuery = summaryBox.query(DailySummary_.date.equals(dayKey)).build();
      final existingSummary = existingQuery.findFirst();
      existingQuery.close();

      if (existingSummary != null) {
        existingSummary.summaryText += '\n${summaryDescription.toString()}';
        existingSummary.totalScreenTimeMinutes += screenTimeMinutes;
        existingSummary.totalSpent += totalSpent;
        summaryBox.put(existingSummary);
      } else {
        final newSummary = DailySummary(
          date: dayKey,
          summaryText: summaryDescription.toString(),
          totalScreenTimeMinutes: screenTimeMinutes,
          totalSpent: totalSpent,
          createdAt: now,
        );
        summaryBox.put(newSummary);
      }

      affectedDates.add(dayKey);
    }

    // 5. Purge pruned memory nodes from disk
    final idsToRemove = nodesToPrune.map((node) => node.id).toList();
    memoryBox.removeMany(idsToRemove);

    debugPrint('[StoragePrunerService] Successfully pruned ${idsToRemove.length} nodes across ${affectedDates.length} days.');

    return PruneReport(
      prunedNodeCount: idsToRemove.length,
      summariesProcessed: affectedDates.length,
      affectedDates: affectedDates,
      executedAt: now,
    );
  }

  /// Extracts screen time minutes from content or JSON metadata.
  int _parseMinutes(String content, String metadataJson) {
    if (metadataJson.isNotEmpty) {
      try {
        final map = jsonDecode(metadataJson);
        if (map is Map && map.containsKey('minutes')) {
          final val = map['minutes'];
          if (val is num) return val.toInt();
        }
      } catch (_) {}
    }
    // Fallback regex search for "X mins" or "X minutes"
    final match = RegExp(r'(\d+)\s*(?:mins?|minutes?)', caseSensitive: false).firstMatch(content);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '0') ?? 0;
    }
    return 0;
  }

  /// Extracts financial spending amount from content or JSON metadata.
  double _parseSpent(String content, String metadataJson) {
    if (metadataJson.isNotEmpty) {
      try {
        final map = jsonDecode(metadataJson);
        if (map is Map && map.containsKey('amount')) {
          final val = map['amount'];
          if (val is num) return val.toDouble();
        }
      } catch (_) {}
    }
    // Fallback regex search for "$X.XX" or "USD X"
    final match = RegExp(r'(?:\$|usd\s*)(\d+(?:\.\d{1,2})?)', caseSensitive: false).firstMatch(content);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '0.0') ?? 0.0;
    }
    return 0.0;
  }
}
