import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/byok_key_manager.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/hybrid_rag_orchestrator.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/intent_router_service.dart';
import 'package:matrix_ai_os/features/ai_brain/presentation/providers/ai_brain_providers.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/services/voice_assistant_service.dart';

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
  final PendingActionConfirmation? pendingAction;
  final ActionResult? actionResult;
  final String? mcpBadge;

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
    this.pendingAction,
    this.actionResult,
    this.mcpBadge,
  });

  bool get hasBadges =>
      !isUser &&
      (tokensMasked > 0 ||
          localMemoriesUsed > 0 ||
          webResultsUsed > 0 ||
          isOfflineEngine ||
          intent != null ||
          actionResult != null ||
          mcpBadge != null);
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

/// StateNotifier controlling the Assistant Chat interaction, Action Dispatcher, and RAG pipeline.
class ChatController extends StateNotifier<ChatState> {
  final HybridRagOrchestrator _orchestrator;
  final ByokKeyManager _byokManager;
  final ActionDispatcherService _actionDispatcher;
  final VoiceAssistantService _voiceService;

  ChatController({
    required HybridRagOrchestrator orchestrator,
    required ByokKeyManager byokManager,
    required ActionDispatcherService actionDispatcher,
    required VoiceAssistantService voiceService,
  })  : _orchestrator = orchestrator,
        _byokManager = byokManager,
        _actionDispatcher = actionDispatcher,
        _voiceService = voiceService,
        super(
          ChatState(
            messages: [
              ChatMessage(
                id: 'welcome',
                text: 'Greetings. I am **Matrix AI OS**.\n\n'
                    '• **Zero Data Leakage:** All your data remains AES-256 encrypted locally.\n'
                    '• **Local PII Masking:** Account numbers, phone numbers, and IDs are redacted before any cloud query.\n'
                    '• **Action Execution:** Voice/chat actions for calls, WhatsApp, screen reading with Human-in-the-Loop gates.\n'
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

  /// Sends a user prompt through Action Dispatcher or Hybrid RAG pipeline.
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
      // 1. Check if user query matches a phone action command
      final action = _actionDispatcher.parseActionIntent(clean);
      if (action != null) {
        if (action.isSensitive) {
          // Human-in-the-Loop Confirmation Gate
          final pending = await _actionDispatcher.processAction(action) as PendingActionConfirmation;

          final confirmationMsg = ChatMessage(
            id: 'pending_${DateTime.now().millisecondsSinceEpoch}',
            text: '⚠️ **Action Confirmation Gate**\n\n'
                'Please review and approve before executing:\n'
                '• **Action:** ${action.description}\n'
                '• **Type:** ${action.type.displayName}',
            isUser: false,
            timestamp: DateTime.now(),
            pendingAction: pending,
            isOfflineEngine: true,
            providerUsed: 'Action Dispatcher',
          );

          state = state.copyWith(
            messages: [...state.messages, confirmationMsg],
            isLoading: false,
          );

          await _voiceService.speak('Please confirm action: ${action.description}');
          return;
        } else {
          // Safe action: execute directly
          final result = await _actionDispatcher.executeConfirmedAction(action);

          String displayText;
          if (action.type == ActionType.readScreen) {
            final screenText = result.data as String? ?? '';
            displayText = screenText.isNotEmpty
                ? '📱 **Foreground Screen Content:**\n\n$screenText'
                : '📱 Screen is empty or Accessibility Service is not enabled.';
          } else {
            displayText = '⚡ **Action Executed:** ${result.message}';
          }

          final actionMsg = ChatMessage(
            id: 'action_${DateTime.now().millisecondsSinceEpoch}',
            text: displayText,
            isUser: false,
            timestamp: DateTime.now(),
            actionResult: result,
            isOfflineEngine: true,
            providerUsed: 'Action Executor',
          );

          state = state.copyWith(
            messages: [...state.messages, actionMsg],
            isLoading: false,
          );

          await _voiceService.speak(result.message);
          return;
        }
      }

      // 2. Standard conversational Hybrid RAG query
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
        mcpBadge: response.mcpBadge,
      );

      state = state.copyWith(
        messages: [...state.messages, aiMsg],
        isLoading: false,
      );

      // Voice response if enabled
      await _voiceService.speak(response.text);
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

  /// Confirms and executes an approved pending action from the UI.
  Future<void> confirmPendingAction(PendingActionConfirmation pending) async {
    final result = await _actionDispatcher.executeConfirmedAction(pending.action);

    final resultMsg = ChatMessage(
      id: 'approved_${DateTime.now().millisecondsSinceEpoch}',
      text: result.success
          ? '✅ **Action Approved & Executed:**\n${result.message}'
          : '⚠️ **Action Failed:** ${result.message}',
      isUser: false,
      timestamp: DateTime.now(),
      actionResult: result,
      isOfflineEngine: true,
      providerUsed: 'Action Executor',
    );

    state = state.copyWith(
      messages: [...state.messages, resultMsg],
    );

    await _voiceService.speak(result.message);
  }

  /// Cancels a pending action from the UI.
  void cancelPendingAction(PendingActionConfirmation pending) {
    final cancelMsg = ChatMessage(
      id: 'canceled_${DateTime.now().millisecondsSinceEpoch}',
      text: '❌ **Action Canceled:** User rejected "${pending.action.description}".',
      isUser: false,
      timestamp: DateTime.now(),
      isOfflineEngine: true,
      providerUsed: 'Safety Gate',
    );

    state = state.copyWith(
      messages: [...state.messages, cancelMsg],
    );
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
  final actionDispatcher = ref.watch(actionDispatcherServiceProvider);
  final voiceService = ref.watch(voiceAssistantServiceProvider);
  return ChatController(
    orchestrator: orchestrator,
    byokManager: byokManager,
    actionDispatcher: actionDispatcher,
    voiceService: voiceService,
  );
});
