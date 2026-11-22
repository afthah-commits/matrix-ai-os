import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/byok_key_manager.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/hybrid_rag_orchestrator.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/intent_router_service.dart';
import 'package:matrix_ai_os/features/ai_brain/presentation/providers/ai_brain_providers.dart';

/// Individual message in the Matrix AI OS Assistant chat session.
@immutable
class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final int tokensMasked;
  final int localMemoriesUsed;
  final int webResultsUsed;
  final UserIntent? intent;
  final bool isOfflineEngine;
  final String? providerUsed;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.tokensMasked = 0,
    this.localMemoriesUsed = 0,
    this.webResultsUsed = 0,
    this.intent,
    this.isOfflineEngine = false,
    this.providerUsed,
  });

  bool get hasBadges =>
      !isUser &&
      (tokensMasked > 0 ||
          localMemoriesUsed > 0 ||
          webResultsUsed > 0 ||
          isOfflineEngine ||
          intent != null);
}

/// State for the Assistant Chat session.
@immutable
class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? errorMessage;
  final AiProvider currentProvider;
  final bool isAirGapped;

  const ChatState({
    required this.messages,
    required this.isLoading,
    this.errorMessage,
    required this.currentProvider,
    required this.isAirGapped,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? errorMessage,
    AiProvider? currentProvider,
    bool? isAirGapped,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      currentProvider: currentProvider ?? this.currentProvider,
      isAirGapped: isAirGapped ?? this.isAirGapped,
    );
  }
}

/// StateNotifier controlling the Assistant Chat interaction and RAG pipeline.
class ChatController extends StateNotifier<ChatState> {
  final HybridRagOrchestrator _orchestrator;
  final ByokKeyManager _byokManager;

  ChatController({
    required HybridRagOrchestrator orchestrator,
    required ByokKeyManager byokManager,
  })  : _orchestrator = orchestrator,
        _byokManager = byokManager,
        super(
          ChatState(
            messages: [
              ChatMessage(
                id: 'welcome',
                text: 'Greetings. I am **Matrix AI OS**.\n\n'
                    '• **Zero Data Leakage:** All your data remains AES-256 encrypted locally.\n'
                    '• **Local PII Masking:** Account numbers, phone numbers, and IDs are redacted before any cloud query.\n'
                    '• **Live Web Search:** Real-time news, scores, and general knowledge via DuckDuckGo.\n'
                    '• **Air-Gapped Mode:** Toggle 100% offline local processing anytime in Settings.\n\n'
                    'How may I assist you today?',
                isUser: false,
                timestamp: DateTime.now(),
                isOfflineEngine: true,
                providerUsed: 'Matrix Core',
              ),
            ],
            isLoading: false,
            currentProvider: AiProvider.gemini,
            isAirGapped: false,
          ),
        ) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final offline = await _byokManager.isOfflineOnly();
    final provider = await _byokManager.getSelectedProvider();
    state = state.copyWith(isAirGapped: offline, currentProvider: provider);
  }

  Future<void> refreshSettings() async {
    await _loadSettings();
  }

  /// Sends a user prompt through the Hybrid RAG pipeline.
  Future<void> sendMessage(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || state.isLoading) return;

    final userMsg = ChatMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      text: clean,
      isUser: true,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      errorMessage: null,
    );

    try {
      final response = await _orchestrator.processQuery(clean);

      final aiMsg = ChatMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: response.text,
        isUser: false,
        timestamp: DateTime.now(),
        tokensMasked: response.tokensMasked,
        localMemoriesUsed: response.localMemoriesUsed,
        webResultsUsed: response.webResultsUsed,
        intent: response.intent,
        isOfflineEngine: response.isOfflineEngine,
        providerUsed: response.providerUsed,
      );

      state = state.copyWith(
        messages: [...state.messages, aiMsg],
        isLoading: false,
      );
    } catch (e) {
      final errorMsg = ChatMessage(
        id: 'error_${DateTime.now().millisecondsSinceEpoch}',
        text: 'An error occurred while processing your request: $e',
        isUser: false,
        timestamp: DateTime.now(),
        isOfflineEngine: true,
      );

      state = state.copyWith(
        messages: [...state.messages, errorMsg],
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  void clearChat() {
    state = state.copyWith(
      messages: [
        ChatMessage(
          id: 'cleared',
          text: 'Chat history cleared. All local encrypted memories remain secure in ObjectBox.',
          isUser: false,
          timestamp: DateTime.now(),
          isOfflineEngine: true,
          providerUsed: 'Matrix Core',
        ),
      ],
    );
  }
}

/// Provider for the ChatController.
final chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>((ref) {
  final orchestrator = ref.watch(hybridRagOrchestratorProvider);
  final byokManager = ref.watch(byokKeyManagerProvider);
  return ChatController(
    orchestrator: orchestrator,
    byokManager: byokManager,
  );
});
