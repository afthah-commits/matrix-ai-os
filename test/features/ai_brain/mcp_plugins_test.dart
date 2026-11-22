import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/mcp/mcp_plugin_registry.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/mcp/plugins/device_battery_storage_plugin.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/mcp/plugins/personal_digest_plugin.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/mcp/plugins/quick_math_currency_plugin.dart';

class FakeLocalDatabaseServiceForMcp extends LocalDatabaseService {
  final int fakeSize;
  final int fakeNodes;
  final int fakeEdges;
  final int fakeSummaries;
  final List<DecryptedMemoryNode> fakeMemories;

  FakeLocalDatabaseServiceForMcp({
    this.fakeSize = 1048576, // 1MB
    this.fakeNodes = 42,
    this.fakeEdges = 18,
    this.fakeSummaries = 7,
    this.fakeMemories = const [],
  });

  @override
  Future<int> getDatabaseSizeInBytes() async => fakeSize;

  @override
  int getMemoryNodeCount() => fakeNodes;

  @override
  int getKnowledgeEdgeCount() => fakeEdges;

  @override
  int getDailySummaryCount() => fakeSummaries;

  @override
  Future<List<DecryptedMemoryNode>> getRecentDecryptedNodes({int limit = 50}) async =>
      fakeMemories;
}

void main() {
  group('MCP Plugins & Registry Tests', () {
    late FakeLocalDatabaseServiceForMcp fakeDb;

    setUp(() {
      fakeDb = FakeLocalDatabaseServiceForMcp(
        fakeMemories: [
          DecryptedMemoryNode(
            id: 1,
            category: MemoryCategory.screenTime,
            content: 'Active screen time: 180 mins',
            metadataJson: jsonEncode({'totalUsageMinutes': 180}),
            timestamp: DateTime.now(),
            isPinned: false,
          ),
          DecryptedMemoryNode(
            id: 2,
            category: MemoryCategory.transaction,
            content: 'Paid 350 to Supermarket',
            metadataJson: jsonEncode({'amount': 350.0, 'txType': 'debit'}),
            timestamp: DateTime.now(),
            isPinned: false,
          ),
          DecryptedMemoryNode(
            id: 3,
            category: MemoryCategory.callLog,
            content: 'Outgoing call to Alice (12 mins)',
            metadataJson: '{}',
            timestamp: DateTime.now(),
            isPinned: false,
          ),
        ],
      );
    });

    test('DeviceBatteryStoragePlugin handles queries and returns accurate telemetry', () async {
      final plugin = DeviceBatteryStoragePlugin(dbService: fakeDb);

      expect(plugin.canHandle('what is my database storage size?'), isTrue);
      expect(plugin.canHandle('how is device health?'), isTrue);
      expect(plugin.canHandle('who called me?'), isFalse);

      final result = await plugin.execute({'query': 'storage size'});
      expect(result.success, isTrue);
      expect(result.telemetryBadge, equals('Device Health'));
      expect(result.displayText, contains('Local DB Footprint:** 1.00 MB'));
      expect(result.displayText, contains('Budget: < 30 MB'));
      expect(result.displayText, contains('42 active nodes'));
      expect(result.displayText, contains('18 relational links'));
    });

    test('QuickMathCurrencyPlugin converts currencies accurately using offline FX matrix', () async {
      final plugin = QuickMathCurrencyPlugin();

      expect(plugin.canHandle('convert 100 USD to INR'), isTrue);
      expect(plugin.canHandle('50 AED in INR'), isTrue);
      expect(plugin.canHandle('weather in Tokyo'), isFalse);

      // USD to INR (100 * 85.50 = 8550)
      final resultUsd = await plugin.execute({'query': 'convert 100 USD to INR'});
      expect(resultUsd.success, isTrue);
      expect(resultUsd.displayText, contains('8550.00 INR'));
      expect(resultUsd.telemetryBadge, equals('Math & Currency'));

      // AED to INR (50 / 3.6725 * 85.50 ≈ 1164.06)
      final resultAed = await plugin.execute({'query': '50 AED in INR'});
      expect(resultAed.success, isTrue);
      expect(resultAed.displayText, contains('1164.06 INR'));
    });

    test('QuickMathCurrencyPlugin calculates percentages and arithmetic deterministically', () async {
      final plugin = QuickMathCurrencyPlugin();

      // Percentage: 15% of 2400 = 360
      expect(plugin.canHandle('what is 15% of 2400'), isTrue);
      final percentResult = await plugin.execute({'query': 'what is 15% of 2400'});
      expect(percentResult.success, isTrue);
      expect(percentResult.displayText, contains('360.00'));

      // Basic arithmetic: calculate 450 * 2 = 900
      expect(plugin.canHandle('calculate 450 * 2'), isTrue);
      final mathResult = await plugin.execute({'query': 'calculate 450 * 2'});
      expect(mathResult.success, isTrue);
      expect(mathResult.displayText, contains('900.0'));
    });

    test('PersonalDigestPlugin aggregates life metrics into a cohesive encrypted summary', () async {
      final plugin = PersonalDigestPlugin(dbService: fakeDb);

      expect(plugin.canHandle('generate my daily digest'), isTrue);
      expect(plugin.canHandle('summarize my day'), isTrue);

      final result = await plugin.execute({'query': 'daily digest'});
      expect(result.success, isTrue);
      expect(result.telemetryBadge, equals('Life Digest'));
      expect(result.displayText, contains('Personal Life Digest'));
      expect(result.displayText, contains('3.0 hrs (180 mins active)'));
      expect(result.displayText, contains('\$350.00 today'));
      expect(result.displayText, contains('1 calls logged'));
      expect(result.displayText, contains('AES-256 encrypted ObjectBox stores'));
    });

    test('McpPluginRegistry manages discovery, enable/disable toggling, and query execution', () async {
      final mathPlugin = QuickMathCurrencyPlugin();
      final storagePlugin = DeviceBatteryStoragePlugin(dbService: fakeDb);

      final registry = McpPluginRegistry(initialPlugins: [mathPlugin, storagePlugin]);

      expect(registry.getAllPlugins().length, equals(2));
      expect(registry.getEnabledPlugins().length, equals(2));

      // Route math query
      final mathMatch = registry.findMatchingPlugin('convert 100 USD to INR');
      expect(mathMatch, isNotNull);
      expect(mathMatch!.id, equals('quick_math_currency'));

      // Disable math plugin
      registry.setPluginEnabled('quick_math_currency', false);
      expect(registry.isPluginEnabled('quick_math_currency'), isFalse);
      expect(registry.getEnabledPlugins().length, equals(1));

      // After disabling, query should NOT match
      final mathMatchDisabled = registry.findMatchingPlugin('convert 100 USD to INR');
      expect(mathMatchDisabled, isNull);

      // Re-enable and verify processIfMatching executes correctly
      registry.setPluginEnabled('quick_math_currency', true);
      final executed = await registry.processIfMatching('convert 100 USD to INR');
      expect(executed, isNotNull);
      expect(executed!.success, isTrue);
      expect(executed.telemetryBadge, equals('Math & Currency'));
    });
  });
}
