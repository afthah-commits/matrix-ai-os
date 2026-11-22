import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/core/database/models/daily_summary.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/proactive_context_engine.dart';

class FakeLocalDatabaseServiceForProactive extends LocalDatabaseService {
  final List<DailySummary> fakeSummaries;
  final List<DecryptedMemoryNode> fakeMemories;

  FakeLocalDatabaseServiceForProactive({
    this.fakeSummaries = const [],
    this.fakeMemories = const [],
  });

  @override
  List<DailySummary> getAllDailySummaries() => fakeSummaries;

  @override
  Future<List<DecryptedMemoryNode>> getRecentDecryptedNodes({int limit = 50}) async =>
      fakeMemories;
}

void main() {
  group('ProactiveContextEngine Tests', () {
    final now = DateTime(2026, 11, 22, 14, 0);

    test('Generates Spending Spike Alert when today spend significantly exceeds 7-day average', () async {
      final summaries = <DailySummary>[
        DailySummary(
          date: '2026-11-21',
          summaryText: 'Normal day',
          totalScreenTimeMinutes: 120,
          totalSpent: 400.0,
          createdAt: DateTime(2026, 11, 21),
        ),
        DailySummary(
          date: '2026-11-20',
          summaryText: 'Normal day',
          totalScreenTimeMinutes: 100,
          totalSpent: 500.0,
          createdAt: DateTime(2026, 11, 20),
        ),
      ];

      final memories = [
        DecryptedMemoryNode(
          id: 1,
          category: MemoryCategory.transaction,
          content: 'Spent 1800 at electronics store',
          metadataJson: jsonEncode({'amount': 1800.0, 'txType': 'debit', 'merchant': 'Tech Store'}),
          timestamp: DateTime(2026, 11, 22, 11, 30),
          isPinned: false,
        ),
      ];

      final fakeDb = FakeLocalDatabaseServiceForProactive(
        fakeSummaries: summaries,
        fakeMemories: memories,
      );

      final engine = ProactiveContextEngine(dbService: fakeDb);
      final insights = await engine.generateProactiveInsights(referenceDate: now);

      final spendAlert = insights.where((i) => i.type == InsightType.spendingSpike).firstOrNull;
      expect(spendAlert, isNotNull);
      expect(spendAlert!.title, equals('Spending Spike Detected'));
      expect(spendAlert.message, contains('\$1800.00'));
      expect(spendAlert.message, contains('higher than your 7-day daily average'));
    });

    test('Generates Screen Time Nudge when daily usage reaches or exceeds 240 minutes', () async {
      final memories = [
        DecryptedMemoryNode(
          id: 2,
          category: MemoryCategory.screenTime,
          content: 'Daily screen time: 310 minutes',
          metadataJson: jsonEncode({'totalUsageMinutes': 310, 'date': '2026-11-22'}),
          timestamp: DateTime(2026, 11, 22, 12, 0),
          isPinned: false,
        ),
      ];

      final fakeDb = FakeLocalDatabaseServiceForProactive(
        fakeSummaries: const [],
        fakeMemories: memories,
      );

      final engine = ProactiveContextEngine(dbService: fakeDb);
      final insights = await engine.generateProactiveInsights(referenceDate: now);

      final screenNudge = insights.where((i) => i.type == InsightType.screenTimeNudge).firstOrNull;
      expect(screenNudge, isNotNull);
      expect(screenNudge!.title, equals('Digital Wellbeing Nudge'));
      expect(screenNudge.message, contains('310 mins'));
      expect(screenNudge.message, contains('digital detox'));
    });

    test('Generates Upcoming Ticket Alert for bookings scheduled within 48 hours', () async {
      // 24 hours in the future
      final travelDate = now.add(const Duration(hours: 24));
      final dateString = travelDate.toIso8601String();

      final memories = [
        DecryptedMemoryNode(
          id: 3,
          category: MemoryCategory.ocrDoc,
          content: 'Flight booking to Mumbai for $dateString, PNR: 6F8K2L',
          metadataJson: jsonEncode({
            'classification': {
              'type': 'ticketBooking',
              'summary': 'Airline ticket to Mumbai',
              'entities': {
                'date': dateString,
                'idNumber': '6F8K2L',
                'merchantOrIssuer': 'IndiGo Airlines',
              }
            }
          }),
          timestamp: DateTime(2026, 11, 20),
          isPinned: true,
        ),
      ];

      final fakeDb = FakeLocalDatabaseServiceForProactive(
        fakeSummaries: const [],
        fakeMemories: memories,
      );

      final engine = ProactiveContextEngine(dbService: fakeDb);
      final insights = await engine.generateProactiveInsights(referenceDate: now);

      final ticketAlert = insights.where((i) => i.type == InsightType.upcomingTicket).firstOrNull;
      expect(ticketAlert, isNotNull);
      expect(ticketAlert!.title, contains('Upcoming Travel'));
      expect(ticketAlert.message, contains('6F8K2L'));
      expect(ticketAlert.message, contains('24 hours'));
    });
  });
}
