import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/features/ai_brain/data/tools/live_web_search_tool.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/byok_key_manager.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/hybrid_rag_orchestrator.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/intent_router_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/knowledge_graph_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/pii_masking_service.dart';

// Fake ByokKeyManager for testing without device secure storage
class FakeByokKeyManager extends ByokKeyManager {
  bool offlineMode = false;
  String? geminiKey;
  String? openAiKey;
  AiProvider currentProvider = AiProvider.gemini;

  @override
  Future<bool> isOfflineOnly() async => offlineMode;

  @override
  Future<AiProvider> getSelectedProvider() async => currentProvider;

  @override
  Future<String?> getGeminiApiKey() async => geminiKey;

  @override
  Future<String?> getOpenAiApiKey() async => openAiKey;

  @override
  Future<bool> hasActiveKey() async {
    if (offlineMode) return false;
    if (currentProvider == AiProvider.gemini) return geminiKey != null && geminiKey!.isNotEmpty;
    if (currentProvider == AiProvider.openAiCompatible) {
      return openAiKey != null && openAiKey!.isNotEmpty;
    }
    return false;
  }
}

// Fake KnowledgeGraphService returning deterministic memories
class FakeKnowledgeGraphService extends KnowledgeGraphService {
  final List<DecryptedMemoryNode> fakeMemories;
  final List<DecryptedKnowledgeEdge> fakeEdges;

  FakeKnowledgeGraphService({
    this.fakeMemories = const [],
    this.fakeEdges = const [],
  }) : super(dbService: _FakeLocalDatabaseService());

  @override
  Future<KnowledgeQueryResult> queryRelatedMemories(String query, {int limit = 10}) async {
    return KnowledgeQueryResult(
      query: query,
      edges: fakeEdges,
      memories: fakeMemories,
      relevanceScore: 5.0,
    );
  }
}

class _FakeLocalDatabaseService extends LocalDatabaseService {}

void main() {
  group('HybridRagOrchestrator Tests', () {
    late PiiMaskingService piiService;
    late IntentRouterService intentRouter;
    late FakeByokKeyManager fakeByok;

    setUp(() {
      piiService = PiiMaskingService();
      intentRouter = IntentRouterService();
      fakeByok = FakeByokKeyManager();
    });

    test('Runs deterministic local engine when offline or no API key is set', () async {
      fakeByok.offlineMode = true; // Air-Gapped mode

      final fakeKg = FakeKnowledgeGraphService(
        fakeMemories: [
          DecryptedMemoryNode(
            id: 1,
            category: 'transaction',
            content: 'Paid Rs. 450 to Axis Bank for groceries',
            metadataJson: '{"amount": 450.0, "merchant": "Axis Bank"}',
            timestamp: DateTime.now(),
            isPinned: false,
          ),
        ],
      );

      final orchestrator = HybridRagOrchestrator(
        knowledgeGraphService: fakeKg,
        piiMaskingService: piiService,
        webSearchTool: LiveWebSearchTool(),
        intentRouter: intentRouter,
        byokManager: fakeByok,
      );

      final response = await orchestrator.processQuery('How much did I spend?');

      expect(response.isOfflineEngine, isTrue);
      expect(response.tokensMasked, 0); // No cloud transmission = no masking needed
      expect(response.localMemoriesUsed, equals(1));
      expect(response.text, contains('Paid Rs. 450 to Axis Bank'));
      expect(response.text, contains('Air-Gapped Mode active'));
    });

    test('Zero Data Leakage: Anonymizes personal PII before cloud dispatch and unmasks upon return', () async {
      fakeByok.offlineMode = false;
      fakeByok.geminiKey = 'fake_test_gemini_key_12345';
      fakeByok.currentProvider = AiProvider.gemini;

      // Local memory contains sensitive PII: Account **3948, Passport Z9482014, Phone 9876543210
      final fakeKg = FakeKnowledgeGraphService(
        fakeMemories: [
          DecryptedMemoryNode(
            id: 1,
            category: 'ocr_doc',
            content: 'Passport document number: Z9482014, Emergency phone: +91 98765 43210',
            metadataJson: '{}',
            timestamp: DateTime.now(),
            isPinned: true,
          ),
          DecryptedMemoryNode(
            id: 2,
            category: 'transaction',
            content: 'Debited Rs. 1500 from Account **3948',
            metadataJson: '{}',
            timestamp: DateTime.now(),
            isPinned: false,
          ),
        ],
      );

      String? capturedOutboundPayload;

      final mockClient = MockClient((request) async {
        capturedOutboundPayload = request.body;

        // Simulate Gemini replying with the privacy tokens preserved
        final responseJson = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text':
                        'Your passport is [ID_DOC_1], emergency contact is [PHONE_1], and recent charge was from [ACCOUNT_1].'
                  }
                ]
              }
            }
          ]
        };

        return http.Response(jsonEncode(responseJson), 200);
      });

      final orchestrator = HybridRagOrchestrator(
        knowledgeGraphService: fakeKg,
        piiMaskingService: piiService,
        webSearchTool: LiveWebSearchTool(),
        intentRouter: intentRouter,
        byokManager: fakeByok,
        client: mockClient,
      );

      final response = await orchestrator.processQuery('What is my passport and account info?');

      // 1. Verify that raw PII NEVER escaped in the outbound HTTP request to the cloud
      expect(capturedOutboundPayload, isNotNull);
      expect(capturedOutboundPayload!.contains('Z9482014'), isFalse);
      expect(capturedOutboundPayload!.contains('+91 98765 43210'), isFalse);
      expect(capturedOutboundPayload!.contains('**3948'), isFalse);

      // Verify privacy tokens WERE present in outbound payload
      expect(capturedOutboundPayload!.contains('[ID_DOC_1]'), isTrue);
      expect(capturedOutboundPayload!.contains('[PHONE_1]'), isTrue);
      expect(capturedOutboundPayload!.contains('[ACCOUNT_1]'), isTrue);

      // 2. Verify that on-device restoration unmasked the tokens accurately
      expect(response.tokensMasked, greaterThanOrEqualTo(3));
      expect(response.isOfflineEngine, isFalse);
      expect(response.text, contains('Z9482014'));
      expect(response.text, contains('+91 98765 43210'));
      expect(response.text, contains('**3948'));
    });
  });
}
