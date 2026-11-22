import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/features/device_ingestion/data/datasources/device_stats_native_datasource.dart';
import 'package:matrix_ai_os/features/device_ingestion/domain/models/transaction_notification_model.dart';

/// Handler responsible for intercepting, parsing, and encrypting transaction
/// alerts and important messaging notifications from MatrixNotificationListener.
class NotificationIngestionHandler {
  final DeviceStatsNativeDataSource _dataSource;
  final LocalDatabaseService _dbService;

  NotificationIngestionHandler({
    required DeviceStatsNativeDataSource dataSource,
    required LocalDatabaseService dbService,
  })  : _dataSource = dataSource,
        _dbService = dbService {
    // Listen for real-time notifications when Flutter engine is active
    _dataSource.setNotificationListener(_processIncomingNotification);
  }

  /// Processes and encrypts an incoming notification map.
  Future<void> _processIncomingNotification(Map<String, dynamic> rawNotification) async {
    try {
      final category = rawNotification['category'] as String? ?? 'notification';

      if (category == 'transaction') {
        final tx = TransactionNotification.fromMap(rawNotification);

        final amountStr = tx.amount > 0 ? '\$${tx.amount.toStringAsFixed(2)}' : '';
        final typeStr = tx.txType.toUpperCase();
        final content = 'Bank $typeStr: $amountStr to ${tx.merchant} ${tx.accountRef.isNotEmpty ? "(A/c ${tx.accountRef})" : ""}';

        final metadataJson = jsonEncode(tx.toMap());

        final node = await _dbService.insertMemoryNode(
          category: MemoryCategory.transaction,
          content: content,
          metadataJson: metadataJson,
          timestamp: tx.timestamp,
        );

        debugPrint('[NotificationIngestionHandler] Saved encrypted transaction MemoryNode #${node.id} ($amountStr).');
      } else {
        // High-importance communication alert (SMS/WhatsApp/Signal)
        final title = rawNotification['title'] as String? ?? 'Notification';
        final text = rawNotification['text'] as String? ?? '';
        final timestampEpoch = (rawNotification['timestamp'] as num?)?.toInt() ?? 0;
        final timestamp = timestampEpoch > 0
            ? DateTime.fromMillisecondsSinceEpoch(timestampEpoch)
            : DateTime.now();

        final content = '[$title] $text';
        final metadataJson = jsonEncode(rawNotification);

        final node = await _dbService.insertMemoryNode(
          category: MemoryCategory.note,
          content: content,
          metadataJson: metadataJson,
          timestamp: timestamp,
        );

        debugPrint('[NotificationIngestionHandler] Saved encrypted alert MemoryNode #${node.id}.');
      }
    } catch (e) {
      debugPrint('[NotificationIngestionHandler] Error processing notification: $e');
    }
  }

  /// Drains any notifications that were buffered in Kotlin while Flutter was detached or backgrounded.
  Future<int> drainBufferedNotifications() async {
    try {
      final bufferedList = await _dataSource.getBufferedNotifications();
      if (bufferedList.isEmpty) return 0;

      for (final raw in bufferedList) {
        await _processIncomingNotification(raw);
      }

      debugPrint('[NotificationIngestionHandler] Drained ${bufferedList.length} buffered notifications.');
      return bufferedList.length;
    } catch (e) {
      debugPrint('[NotificationIngestionHandler] Failed draining buffered notifications: $e');
      return 0;
    }
  }
}
