import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/autonomous_agent_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/byok_key_manager.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/hybrid_rag_orchestrator.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/intent_router_service.dart';
import 'package:matrix_ai_os/features/ai_brain/presentation/providers/ai_brain_providers.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/services/voice_assistant_service.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/deep_document_finder_service.dart';

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
  final List<AgentExecutionStep> executionSteps;
  final List<DocumentMatchResult> matchedDocuments;

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
    this.executionSteps = const [],
    this.matchedDocuments = const [],
  });

  bool get hasBadges =>
      !isUser &&
      (tokensMasked > 0 ||
          localMemoriesUsed > 0 ||
          webResultsUsed > 0 ||
          isOfflineEngine ||
          intent != null ||
          actionResult != null ||
          mcpBadge != null ||
          executionSteps.isNotEmpty ||
          matchedDocuments.isNotEmpty);
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
    bool clearError = false,
    AiProvider? currentProvider,
    bool? isAirGapped,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
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
      messages: List<ChatMessage>.unmodifiable([...state.messages, userMsg]),
      isLoading: true,
      clearError: true,
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
            executionSteps: [
              AgentExecutionStep(
                stepName: '🔍 Detected sensitive action: ${action.type.displayName}',
                status: 'running',
                timestamp: DateTime.now(),
              ),
              AgentExecutionStep(
                stepName: '⚠️ Safety Gate: Human Approval Required',
                status: 'pending_approval',
                output: action.description,
                timestamp: DateTime.now(),
              ),
            ],
          );

          state = state.copyWith(
            messages: List<ChatMessage>.unmodifiable([...state.messages, confirmationMsg]),
            isLoading: false,
          );

          try {
            await _voiceService.speak('Please confirm action: ${action.description}');
          } catch (e) {
            debugPrint('[ChatController] TTS confirmation speak error: $e');
          }
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

          final steps = <AgentExecutionStep>[
            AgentExecutionStep(
              stepName: '🔍 Resolving action: ${action.description}...',
              status: 'running',
              timestamp: DateTime.now(),
            ),
            AgentExecutionStep(
              stepName: result.success ? '🚀 ${result.message}' : '❌ ${result.message}',
              status: result.success ? 'success' : 'failed',
              output: result.data?.toString(),
              timestamp: DateTime.now(),
            ),
          ];

          final actionMsg = ChatMessage(
            id: 'action_${DateTime.now().millisecondsSinceEpoch}',
            text: displayText,
            isUser: false,
            timestamp: DateTime.now(),
            actionResult: result,
            isOfflineEngine: true,
            providerUsed: 'Action Executor',
            executionSteps: steps,
          );

          state = state.copyWith(
            messages: List<ChatMessage>.unmodifiable([...state.messages, actionMsg]),
            isLoading: false,
          );

          try {
            await _voiceService.speak(result.message);
          } catch (e) {
            debugPrint('[ChatController] TTS action speak error: $e');
          }
          return;
        }
      }

      // 2. Standard conversational Hybrid RAG query
      final response = await _orchestrator.processQuery(clean);

      final aiMsg = ChatMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: response.text.isNotEmpty
            ? response.text
            : 'I processed your query, but no response text was returned.',
        isUser: false,
        timestamp: DateTime.now(),
        tokensMasked: response.tokensMasked,
        localMemoriesUsed: response.localMemoriesUsed,
        webResultsUsed: response.webResultsUsed,
        intent: response.intent,
        isOfflineEngine: response.isOfflineEngine,
        providerUsed: response.providerUsed,
        mcpBadge: response.mcpBadge,
        executionSteps: response.executionSteps,
        pendingAction: response.pendingConfirmation,
        matchedDocuments: response.matchedDocuments,
      );

      state = state.copyWith(
        messages: List<ChatMessage>.unmodifiable([...state.messages, aiMsg]),
        isLoading: false,
      );

      // Voice response if enabled (isolated try-catch so TTS failure never breaks UI)
      try {
        await _voiceService.speak(response.text);
      } catch (e) {
        debugPrint('[ChatController] TTS speak error: $e');
      }
    } catch (e) {
      final errorMsg = ChatMessage(
        id: 'error_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Notice: Could not process request ($e). Matrix Core is operating in offline mode.',
        isUser: false,
        timestamp: DateTime.now(),
        isOfflineEngine: true,
      );

      state = state.copyWith(
        messages: List<ChatMessage>.unmodifiable([...state.messages, errorMsg]),
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
      executionSteps: [
        AgentExecutionStep(
          stepName: '✅ User Approved Action: ${pending.action.description}',
          status: 'success',
          timestamp: DateTime.now(),
        ),
        AgentExecutionStep(
          stepName: result.success ? '🚀 ${result.message}' : '❌ ${result.message}',
          status: result.success ? 'success' : 'failed',
          output: result.data?.toString(),
          timestamp: DateTime.now(),
        ),
      ],
    );

    state = state.copyWith(
      messages: List<ChatMessage>.unmodifiable([...state.messages, resultMsg]),
    );

    try {
      await _voiceService.speak(result.message);
    } catch (_) {}
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
      messages: List<ChatMessage>.unmodifiable([...state.messages, cancelMsg]),
    );
  }

  /// Opens a local document file on the device in native gallery or PDF viewer.
  Future<void> openDocumentFile(String uri, {String? mimeType}) async {
    try {
      final res = await _actionDispatcher.openFileUri(uri, mimeType: mimeType);
      if (res['success'] == true) {
        try {
          await _voiceService.speak('Opening document on your device');
        } catch (_) {}
      } else {
        try {
          await _voiceService.speak('Could not open file');
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[ChatNotifier] Error opening document: $e');
    }
  }

  void clearChat() {
    state = state.copyWith(
      clearError: true,
      messages: List<ChatMessage>.unmodifiable([
        ChatMessage(
          id: 'cleared',
          text: 'Chat history cleared. All local encrypted memories remain secure in ObjectBox.',
          isUser: false,
          timestamp: DateTime.now(),
          isOfflineEngine: true,
          providerUsed: 'Matrix Core',
        ),
      ]),
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
