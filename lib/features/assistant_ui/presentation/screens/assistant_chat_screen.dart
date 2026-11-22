import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ai_brain/presentation/providers/ai_brain_providers.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/controllers/chat_controller.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/screens/ai_settings_modal.dart';

/// Full-featured, privacy-first conversational Assistant Chat Screen
/// with Voice UI (STT/TTS) and Action Confirmation Gates.
class AssistantChatScreen extends ConsumerStatefulWidget {
  const AssistantChatScreen({super.key});

  @override
  ConsumerState<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends ConsumerState<AssistantChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const _quickPrompts = [
    'How much did I spend this week?',
    'Convert 100 USD to INR',
    'Device storage status',
    'Generate daily digest',
    'Who called me recently?',
    'What is my passport number?',
    'Read my screen',
    'Open YouTube',
    'Call +91 98765 43210',
    'Latest tech news',
  ];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend([String? presetText]) {
    final query = presetText ?? _inputController.text;
    if (query.trim().isEmpty) return;

    ref.read(chatControllerProvider.notifier).sendMessage(query);
    _inputController.clear();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);
    final voiceService = ref.watch(voiceAssistantServiceProvider);

    const primaryEmerald = Color(0xFF10B981);
    const neonCyan = Color(0xFF06B6D4);
    const accentViolet = Color(0xFF8B5CF6);
    const amberAlert = Color(0xFFF59E0B);
    const surfaceCard = Color(0xFF111827);
    const bgContainer = Color(0xFF0B0F19);
    const borderColor = Color(0xFF1F2937);

    // Auto-scroll on new message
    ref.listen<ChatState>(chatControllerProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length ||
          previous?.isLoading != next.isLoading) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: bgContainer,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primaryEmerald.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primaryEmerald.withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.auto_awesome, color: primaryEmerald, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Matrix AI Assistant',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
                Text(
                  chatState.isAirGapped
                      ? '🛡️ Air-Gapped Mode'
                      : '🔒 Zero-Leakage PII Masking',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: chatState.isAirGapped ? primaryEmerald : neonCyan,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Voice Output Speaker Toggle
          IconButton(
            tooltip: voiceService.isTtsEnabled ? 'Mute AI Voice' : 'Enable AI Voice',
            icon: Icon(
              voiceService.isTtsEnabled ? Icons.volume_up : Icons.volume_off,
              color: voiceService.isTtsEnabled ? primaryEmerald : Colors.white38,
              size: 20,
            ),
            onPressed: () {
              voiceService.toggleTts(!voiceService.isTtsEnabled);
            },
          ),
          IconButton(
            tooltip: 'Clear Chat',
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white60, size: 20),
            onPressed: () {
              ref.read(chatControllerProvider.notifier).clearChat();
            },
          ),
          IconButton(
            tooltip: 'AI & BYOK Settings',
            icon: const Icon(Icons.tune, color: primaryEmerald, size: 20),
            onPressed: () => AiSettingsModal.show(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Live listening pulse indicator bar
          if (voiceService.isListening)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: amberAlert.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: amberAlert,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      voiceService.lastRecognizedWords.isNotEmpty
                          ? 'Listening: "${voiceService.lastRecognizedWords}"'
                          : 'Listening for your voice command...',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: amberAlert,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => voiceService.stopListening(),
                    child: const Text('Stop', style: TextStyle(color: amberAlert, fontSize: 11)),
                  ),
                ],
              ),
            ),

          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              itemCount: chatState.messages.length + (chatState.isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == chatState.messages.length) {
                  return _buildLoadingBubble(primaryEmerald, surfaceCard);
                }
                final msg = chatState.messages[index];
                return _buildMessageBubble(
                  msg,
                  primaryEmerald,
                  neonCyan,
                  accentViolet,
                  amberAlert,
                  surfaceCard,
                  borderColor,
                );
              },
            ),
          ),

          // Quick Prompt Suggestions
          Container(
            height: 38,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _quickPrompts.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final prompt = _quickPrompts[idx];
                return ActionChip(
                  label: Text(
                    prompt,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                  backgroundColor: surfaceCard,
                  side: const BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  onPressed: () => _handleSend(prompt),
                );
              },
            ),
          ),

          // Input Bar with Mic button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Microphone Push-to-Talk button
                  GestureDetector(
                    onTap: () async {
                      if (voiceService.isListening) {
                        await voiceService.stopListening();
                      } else {
                        await voiceService.startListening(
                          onResult: (text) {
                            if (text.trim().isNotEmpty) {
                              _handleSend(text);
                            }
                          },
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: voiceService.isListening
                            ? amberAlert.withValues(alpha: 0.2)
                            : surfaceCard,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: voiceService.isListening ? amberAlert : borderColor,
                          width: voiceService.isListening ? 1.5 : 1.0,
                        ),
                      ),
                      child: Icon(
                        voiceService.isListening ? Icons.mic : Icons.mic_none,
                        color: voiceService.isListening ? amberAlert : primaryEmerald,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSend(),
                      decoration: InputDecoration(
                        hintText: 'Ask Matrix or command (e.g. Call, WhatsApp, Read screen)...',
                        hintStyle: const TextStyle(fontSize: 11, color: Colors.white38),
                        filled: true,
                        fillColor: surfaceCard,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: primaryEmerald),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: primaryEmerald,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primaryEmerald.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.black, size: 18),
                      onPressed: chatState.isLoading ? null : () => _handleSend(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    ChatMessage msg,
    Color primaryEmerald,
    Color neonCyan,
    Color accentViolet,
    Color amberAlert,
    Color surfaceCard,
    Color borderColor,
  ) {
    final timeStr = DateFormat('HH:mm').format(msg.timestamp);

    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF065F46),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
            border: Border.all(
              color: primaryEmerald.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                msg.text,
                style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                timeStr,
                style: const TextStyle(fontSize: 9, color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }

    // AI Message bubble
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: surfaceCard,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(
            color: msg.pendingAction != null ? amberAlert.withValues(alpha: 0.5) : borderColor,
            width: msg.pendingAction != null ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Transparent Privacy & Telemetry Badges
            if (msg.hasBadges) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (msg.pendingAction != null)
                    _buildBadge(
                      Icons.shield_outlined,
                      'Human Confirmation Required',
                      amberAlert,
                    ),
                  if (msg.intent != null)
                    _buildBadge(
                      Icons.category_outlined,
                      msg.intent!.label,
                      Colors.amber,
                    ),
                  if (msg.tokensMasked > 0)
                    _buildBadge(
                      Icons.lock_outline,
                      '${msg.tokensMasked} PII Masked',
                      primaryEmerald,
                    ),
                  if (msg.localMemoriesUsed > 0)
                    _buildBadge(
                      Icons.psychology_outlined,
                      '${msg.localMemoriesUsed} Memories',
                      neonCyan,
                    ),
                  if (msg.webResultsUsed > 0)
                    _buildBadge(
                      Icons.language,
                      '${msg.webResultsUsed} Web Results',
                      const Color(0xFF38BDF8),
                    ),
                  if (msg.mcpBadge != null)
                    _buildBadge(
                      Icons.extension_outlined,
                      'MCP: ${msg.mcpBadge!}',
                      const Color(0xFF10B981),
                    ),
                  if (msg.isOfflineEngine)
                    _buildBadge(
                      Icons.offline_bolt_outlined,
                      'Offline Engine',
                      accentViolet,
                    )
                  else if (msg.providerUsed != null)
                    _buildBadge(
                      Icons.cloud_done_outlined,
                      msg.providerUsed!,
                      accentViolet,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 8),
            ],

            SelectableText(
              msg.text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFF3F4F6),
                height: 1.45,
              ),
            ),

            // Action Confirmation Card for Sensitive Actions
            if (msg.pendingAction != null) ...[
              const SizedBox(height: 12),
              _buildActionConfirmationCard(msg.pendingAction!, primaryEmerald, amberAlert),
            ],

            const SizedBox(height: 6),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                timeStr,
                style: const TextStyle(fontSize: 9, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionConfirmationCard(
    PendingActionConfirmation pending,
    Color primaryEmerald,
    Color amberAlert,
  ) {
    final controller = ref.read(chatControllerProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: amberAlert.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pending.action.type == ActionType.callContact
                    ? Icons.phone_forwarded
                    : Icons.send,
                color: amberAlert,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pending.action.description,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => controller.cancelPendingAction(pending),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => controller.confirmPendingAction(pending),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryEmerald,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Approve Action',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble(Color primaryEmerald, Color surfaceCard) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primaryEmerald.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primaryEmerald,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Matrix AI is reasoning (PII check & context assembly)...',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
