import 'dart:convert';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/mcp/matrix_mcp_plugin.dart';

/// Built-in MCP Plugin: Personal Life Digest aggregating multi-modal on-device memories.
class PersonalDigestPlugin implements MatrixMcpPlugin {
  final LocalDatabaseService _dbService;

  PersonalDigestPlugin({required LocalDatabaseService dbService})
      : _dbService = dbService;

  @override
  String get id => 'personal_digest';

  @override
  String get name => 'Personal Life Digest';

  @override
  String get description =>
      'Aggregates daily screen time, expenses, calls, and upcoming travel into a cohesive encrypted life digest.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
      };

  @override
  bool canHandle(String query) {
    final lower = query.trim().toLowerCase();
    return lower.contains('digest') ||
        lower.contains('summarize my day') ||
        lower.contains('my day in review') ||
        lower.contains('daily overview') ||
        lower.contains('my summary for today');
  }

  @override
  Future<McpPluginResult> execute(Map<String, dynamic> args) async {
    try {
      final now = DateTime.now();
      final recentMemories = await _dbService.getRecentDecryptedNodes(limit: 60);

      int totalScreenTime = 0;
      double totalDebit = 0.0;
      int callCount = 0;
      final recentCalls = <String>[];
      final upcomingTickets = <String>[];

      for (final m in recentMemories) {
        if (_isSameDay(m.timestamp, now)) {
          // Screen Time
          if (m.category == MemoryCategory.screenTime && m.metadataJson.isNotEmpty) {
            try {
              final data = jsonDecode(m.metadataJson) as Map<String, dynamic>;
              final mins = (data['totalUsageMinutes'] as num?)?.toInt() ?? 0;
              if (mins > totalScreenTime) totalScreenTime = mins;
            } catch (_) {}
          }

          // Transactions
          if (m.category == MemoryCategory.transaction && m.metadataJson.isNotEmpty) {
            try {
              final data = jsonDecode(m.metadataJson) as Map<String, dynamic>;
              final type = data['txType'] as String? ?? 'debit';
              final amt = (data['amount'] as num?)?.toDouble() ?? 0.0;
              if (type == 'debit') totalDebit += amt;
            } catch (_) {}
          }

          // Calls
          if (m.category == MemoryCategory.callLog) {
            callCount++;
            if (m.content.isNotEmpty && recentCalls.length < 3) {
              recentCalls.add(m.content);
            }
          }
        }

        // Tickets & Travel (any recent pinned OCR doc)
        if (m.category == MemoryCategory.ocrDoc && m.isPinned) {
          if (upcomingTickets.length < 2) {
            upcomingTickets.add(m.content);
          }
        }
      }

      final buffer = StringBuffer();
      buffer.writeln('📋 **Matrix AI OS — Personal Life Digest (MCP):**\n');

      final screenHours = (totalScreenTime / 60).toStringAsFixed(1);
      buffer.writeln('⏱️ **Screen Time:** $screenHours hrs ($totalScreenTime mins active)');
      buffer.writeln('💳 **Expenses Logged:** \$${totalDebit.toStringAsFixed(2)} today');
      buffer.writeln('📞 **Communications:** $callCount calls logged');

      if (recentCalls.isNotEmpty) {
        buffer.writeln('   • Recent: ${recentCalls.join(' • ')}');
      }

      if (upcomingTickets.isNotEmpty) {
        buffer.writeln('\n✈️ **Upcoming Scheduled Journey / Tickets:**');
        for (final t in upcomingTickets) {
          buffer.writeln('   • $t');
        }
      }

      buffer.writeln('\n🔒 *Compiled 100% on-device from AES-256 encrypted ObjectBox stores.*');

      return McpPluginResult(
        success: true,
        displayText: buffer.toString().trim(),
        rawData: {
          'screenTimeMinutes': totalScreenTime,
          'totalDebit': totalDebit,
          'callCount': callCount,
          'ticketsCount': upcomingTickets.length,
        },
        telemetryBadge: 'Life Digest',
      );
    } catch (e) {
      return McpPluginResult(
        success: false,
        displayText: 'Failed to generate personal life digest: $e',
        telemetryBadge: 'Life Digest',
      );
    }
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
