import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/database/database_providers.dart';
import 'package:matrix_ai_os/features/ai_brain/data/tools/live_web_search_tool.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/byok_key_manager.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/hybrid_rag_orchestrator.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/intent_router_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/knowledge_graph_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/pii_masking_service.dart';

/// Provider for the On-Device Personal Knowledge Graph engine.
final knowledgeGraphServiceProvider = Provider<KnowledgeGraphService>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  return KnowledgeGraphService(dbService: dbService);
});

/// Provider for deterministic on-device PII masking and restoration.
final piiMaskingServiceProvider = Provider<PiiMaskingService>((ref) {
  return PiiMaskingService();
});

/// Provider for free, zero-key live web search.
final liveWebSearchToolProvider = Provider<LiveWebSearchTool>((ref) {
  return LiveWebSearchTool();
});

/// Provider for query intent router.
final intentRouterServiceProvider = Provider<IntentRouterService>((ref) {
  return IntentRouterService();
});

/// Provider for BYOK key storage.
final byokKeyManagerProvider = Provider<ByokKeyManager>((ref) {
  return ByokKeyManager();
});

/// Provider for the Hybrid RAG Orchestrator.
final hybridRagOrchestratorProvider = Provider<HybridRagOrchestrator>((ref) {
  return HybridRagOrchestrator(
    knowledgeGraphService: ref.watch(knowledgeGraphServiceProvider),
    piiMaskingService: ref.watch(piiMaskingServiceProvider),
    webSearchTool: ref.watch(liveWebSearchToolProvider),
    intentRouter: ref.watch(intentRouterServiceProvider),
    byokManager: ref.watch(byokKeyManagerProvider),
  );
});
