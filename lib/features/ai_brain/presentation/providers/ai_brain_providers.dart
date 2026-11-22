import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/database/database_providers.dart';
import 'package:matrix_ai_os/features/ai_brain/data/tools/live_web_search_tool.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/mcp/mcp_plugin_registry.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/mcp/plugins/device_battery_storage_plugin.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/mcp/plugins/personal_digest_plugin.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/mcp/plugins/quick_math_currency_plugin.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/autonomous_agent_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/byok_key_manager.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/hybrid_rag_orchestrator.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/intent_router_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/knowledge_graph_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/offline_slm_manager.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/pii_masking_service.dart';
import 'package:matrix_ai_os/features/ocr_vision/presentation/providers/ocr_vision_providers.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/proactive_context_engine.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/services/voice_assistant_service.dart';

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

/// Provider for Action Dispatcher Service.
final actionDispatcherServiceProvider = Provider<ActionDispatcherService>((ref) {
  return ActionDispatcherService();
});

/// Provider for Proactive Context Engine.
final proactiveContextEngineProvider = Provider<ProactiveContextEngine>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  return ProactiveContextEngine(dbService: dbService);
});

/// FutureProvider fetching active proactive insights.
final proactiveInsightsProvider = FutureProvider<List<ProactiveInsight>>((ref) async {
  final engine = ref.watch(proactiveContextEngineProvider);
  return engine.generateProactiveInsights();
});

/// FutureProvider checking Accessibility Service enablement.
final accessibilityEnabledProvider = FutureProvider<bool>((ref) async {
  final dispatcher = ref.watch(actionDispatcherServiceProvider);
  return dispatcher.checkAccessibilityEnabled();
});

/// ChangeNotifierProvider for native Voice Assistant (STT & TTS).
final voiceAssistantServiceProvider = ChangeNotifierProvider<VoiceAssistantService>((ref) {
  return VoiceAssistantService();
});

/// ChangeNotifierProvider for on-demand downloadable edge SLMs.
final offlineSlmManagerProvider = ChangeNotifierProvider<OfflineSlmManager>((ref) {
  return OfflineSlmManager();
});

/// ChangeNotifierProvider for Model Context Protocol (MCP) tool registry.
final mcpPluginRegistryProvider = ChangeNotifierProvider<McpPluginRegistry>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  final registry = McpPluginRegistry(
    initialPlugins: [
      DeviceBatteryStoragePlugin(dbService: dbService),
      QuickMathCurrencyPlugin(),
      PersonalDigestPlugin(dbService: dbService),
    ],
  );
  return registry;
});

/// Provider for Autonomous Agent Service.
final autonomousAgentServiceProvider = Provider<AutonomousAgentService>((ref) {
  return AutonomousAgentService(
    actionDispatcher: ref.watch(actionDispatcherServiceProvider),
    knowledgeGraphService: ref.watch(knowledgeGraphServiceProvider),
    documentFinderService: ref.watch(deepDocumentFinderServiceProvider),
  );
});

/// Provider for the Hybrid RAG Orchestrator with SLM & MCP integration.
final hybridRagOrchestratorProvider = Provider<HybridRagOrchestrator>((ref) {
  return HybridRagOrchestrator(
    knowledgeGraphService: ref.watch(knowledgeGraphServiceProvider),
    piiMaskingService: ref.watch(piiMaskingServiceProvider),
    webSearchTool: ref.watch(liveWebSearchToolProvider),
    intentRouter: ref.watch(intentRouterServiceProvider),
    byokManager: ref.watch(byokKeyManagerProvider),
    mcpRegistry: ref.watch(mcpPluginRegistryProvider),
    slmManager: ref.watch(offlineSlmManagerProvider),
    autonomousAgent: ref.watch(autonomousAgentServiceProvider),
  );
});
