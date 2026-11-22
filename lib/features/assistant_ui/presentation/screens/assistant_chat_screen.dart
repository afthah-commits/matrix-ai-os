import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:matrix_ai_os/core/presentation/widgets/matrix_logo_widget.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/autonomous_agent_service.dart';
import 'package:matrix_ai_os/features/ai_brain/presentation/providers/ai_brain_providers.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/controllers/chat_controller.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/screens/ai_settings_modal.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/services/voice_assistant_service.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/deep_document_finder_service.dart';

/// Full-featured, privacy-first conversational Assistant Chat Screen
/// with High-Contrast OLED Dark Layout, Voice UI (STT/TTS),
/// Autonomous ReAct Tool Execution, and Action Confirmation Gates.
class AssistantChatScreen extends ConsumerStatefulWidget {
  const AssistantChatScreen({super.key});

  @override
  ConsumerState<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends ConsumerState<AssistantChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const primaryEmerald = Color(0xFF10B981);
  static const neonCyan = Color(0xFF06B6D4);
  static const accentViolet = Color(0xFF8B5CF6);
  static const amberAlert = Color(0xFFF59E0B);
  static const bgContainer = Color(0xFF090D16);
  static const surfaceCard = Color(0xFF161B22);
  static const borderColor = Color(0xFF30363D);

  static const _quickPrompts = [
    'Find My Passport',
    'Search my documents',
    'Open WhatsApp',
    'Open Camera',
    'Open Settings',
    'Open YouTube',
    'Convert 100 USD to INR',
    'Device storage status',
    'Generate daily digest',
    'What is my passport number?',
    'Read my screen',
    'Call +91 98765 43210',
    'Latest tech news',
    'യൂട്യൂബ് തുറക്കൂ',
    'രാഹുലിന് വാട്സാപ്പിൽ ഹായ് അയക്കൂ',
  ];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool immediate = false}) {
    void doScroll() {
      if (_scrollController.hasClients) {
        if (immediate) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        } else {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());
    Future.delayed(const Duration(milliseconds: 100), () => doScroll());
    Future.delayed(const Duration(milliseconds: 280), () => doScroll());
  }

  void _handleSend([String? presetText]) {
    final query = presetText ?? _inputController.text;
    if (query.trim().isEmpty) return;

    ref.read(chatControllerProvider.notifier).sendMessage(query);
    _inputController.clear();
    _scrollToBottom(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);
    final voiceService = ref.watch(voiceAssistantServiceProvider);

    // Auto-scroll on new message
    ref.listen<ChatState>(chatControllerProvider, (previous, next) {
      if ((previous?.messages.length ?? 0) != next.messages.length ||
          previous?.isLoading != next.isLoading) {
        _scrollToBottom();
      }
    });

    // Listen to voice errors and surface immediate feedback
    ref.listen<VoiceAssistantService>(voiceAssistantServiceProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF7F1D1D),
            content: Row(
              children: [
                const Icon(Icons.mic_off, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    next.errorMessage!,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'Settings',
              textColor: const Color(0xFFFCA5A5),
              onPressed: () => openAppSettings(),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: bgContainer,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            const MatrixLogoWidget(size: 32),
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
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70, size: 21),
            onPressed: () {
              ref.read(chatControllerProvider.notifier).clearChat();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Chat history cleared'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Color(0xFF1F2937),
                ),
              );
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: amberAlert.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: amberAlert,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      voiceService.lastRecognizedWords.isNotEmpty
                          ? 'Listening: "${voiceService.lastRecognizedWords}"'
                          : 'Listening for voice command (English & മലയാളം)...',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: amberAlert,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => voiceService.stopListening(),
                    child: const Text('Stop', style: TextStyle(color: amberAlert, fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Messages List or Empty-State Hero
          Expanded(
            child: chatState.messages.isEmpty
                ? _buildEmptyStateHero()
                : ListView.builder(
                    controller: _scrollController,
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(left: 14, right: 14, top: 12, bottom: 20),
                    itemCount: chatState.messages.length + (chatState.isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == chatState.messages.length) {
                        return _buildLoadingBubble();
                      }
                      final msg = chatState.messages[index];
                      return _buildMessageBubble(msg);
                    },
                  ),
          ),

          // Quick Prompt Suggestions (shown when messages exist)
          if (chatState.messages.isNotEmpty)
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
                      style: const TextStyle(fontSize: 11, color: Color(0xFFE2E8F0)),
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

          // Bottom Input Bar with Mic & Send buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: Color(0xFF1E293B))),
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
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: voiceService.isListening
                            ? amberAlert.withValues(alpha: 0.22)
                            : surfaceCard,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: voiceService.isListening ? amberAlert : primaryEmerald.withValues(alpha: 0.6),
                          width: voiceService.isListening ? 2.0 : 1.2,
                        ),
                        boxShadow: voiceService.isListening
                            ? [
                                BoxShadow(
                                  color: amberAlert.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        voiceService.isListening ? Icons.mic : Icons.mic_none,
                        color: voiceService.isListening ? amberAlert : primaryEmerald,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      style: const TextStyle(fontSize: 14, color: Color(0xFFF0F6FC)),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSend(),
                      decoration: InputDecoration(
                        hintText: 'Ask Matrix or command (EN / മലയാളം)...',
                        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B949E)),
                        filled: true,
                        fillColor: surfaceCard,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: primaryEmerald, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: primaryEmerald,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primaryEmerald.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
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

  /// Empty-State Hero displaying the Custom Matrix AI OS Logo and Quick-Action Chips.
  Widget _buildEmptyStateHero() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          const MatrixLogoWidget(size: 68, withGlow: true),
          const SizedBox(height: 16),
          const Text(
            'Matrix AI OS',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Privacy-First • Autonomous On-Device AI Agent',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: neonCyan,
            ),
          ),
          const SizedBox(height: 16),

          // Security & Capability Badges
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildBadge(Icons.lock, 'AES-256 Storage', primaryEmerald),
              _buildBadge(Icons.shield, 'Zero Cloud Leakage', neonCyan),
              _buildBadge(Icons.translate, 'Bilingual (EN / ML)', accentViolet),
              _buildBadge(Icons.hearing, 'Hey Matrix Wake-Word', const Color(0xFFF59E0B)),
            ],
          ),
          const SizedBox(height: 28),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Quick Commands & Prompts:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Interactive prompt suggestion chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickPrompts.map((prompt) {
              return ActionChip(
                label: Text(
                  prompt,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFE2E8F0)),
                ),
                backgroundColor: surfaceCard,
                side: const BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                onPressed: () => _handleSend(prompt),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final timeStr = DateFormat('HH:mm').format(msg.timestamp);

    // User Message Bubble (Right-aligned, High-Contrast Dark Emerald)
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F3D3E),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
            border: Border.all(
              color: primaryEmerald.withValues(alpha: 0.7),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryEmerald.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SelectableText(
                msg.text,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                timeStr,
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    // AI Assistant Message Bubble (Left-aligned, High-Contrast Slate Charcoal #161B22)
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: surfaceCard,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(
            color: msg.pendingAction != null ? amberAlert.withValues(alpha: 0.7) : borderColor,
            width: msg.pendingAction != null ? 1.5 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HERO: AI Response text in bright 15sp high-contrast readable text
            SelectableText(
              msg.text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.normal,
                color: Color(0xFFF0F6FC),
                height: 1.48,
              ),
            ),

            // Autonomous ReAct Execution Steps Card
            if (msg.executionSteps.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildExecutionStepsCard(msg.executionSteps, primaryEmerald, neonCyan, amberAlert),
            ],

            // Matched Document / Passport / Receipt Card with One-Tap Open
            if (msg.matchedDocuments.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildMatchedDocumentsCard(msg.matchedDocuments, primaryEmerald, neonCyan),
            ],

            // Action Confirmation Card for Sensitive Actions
            if (msg.pendingAction != null) ...[
              const SizedBox(height: 12),
              _buildActionConfirmationCard(msg.pendingAction!, primaryEmerald, amberAlert),
            ],

            // Metadata footer pills (placed below the message so text is always the hero)
            if (msg.hasBadges) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (msg.pendingAction != null)
                    _buildBadge(
                      Icons.shield_outlined,
                      'Human Approval Required',
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
            ],

            const SizedBox(height: 6),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                timeStr,
                style: const TextStyle(fontSize: 10, color: Color(0xFF8B949E)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchedDocumentsCard(
    List<DocumentMatchResult> docs,
    Color primaryEmerald,
    Color neonCyan,
  ) {
    final controller = ref.read(chatControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: docs.map((doc) {
        Color badgeColor = primaryEmerald;
        IconData docIcon = Icons.description;

        switch (doc.category) {
          case 'PASSPORT_ID':
            badgeColor = primaryEmerald;
            docIcon = Icons.badge;
            break;
          case 'TICKET_BOOKING':
            badgeColor = neonCyan;
            docIcon = Icons.confirmation_number;
            break;
          case 'INVOICE_RECEIPT':
            badgeColor = const Color(0xFFF59E0B);
            docIcon = Icons.receipt_long;
            break;
          case 'BANK_STATEMENT':
            badgeColor = const Color(0xFF3B82F6);
            docIcon = Icons.account_balance;
            break;
        }

        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Category Badge
              Row(
                children: [
                  Icon(docIcon, color: badgeColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      doc.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: Text(
                      doc.category,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),

              if (doc.extractedSummary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  doc.extractedSummary,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE2E8F0),
                    height: 1.35,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Key details
              if (doc.keyFields.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: doc.keyFields.entries.where((e) {
                    final v = e.value?.toString() ?? '';
                    return v.isNotEmpty && v != '[]';
                  }).take(3).map((e) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${e.key}: ${e.value}',
                        style: const TextStyle(fontSize: 10, color: Color(0xFFCBD5E1)),
                      ),
                    );
                  }).toList(),
                ),
              ],

              if (doc.fileUri.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => controller.openDocumentFile(doc.fileUri, mimeType: doc.mimeType),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text(
                      'Open File on Device',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: badgeColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
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
        border: Border.all(color: amberAlert.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pending.action.type == ActionType.callContact
                    ? Icons.phone_forwarded
                    : pending.action.type == ActionType.clickUi
                        ? Icons.touch_app
                        : Icons.send,
                color: amberAlert,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pending.action.description,
                  style: const TextStyle(
                    fontSize: 13,
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

  Widget _buildExecutionStepsCard(
    List<AgentExecutionStep> steps,
    Color primaryEmerald,
    Color neonCyan,
    Color amberAlert,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF090E17),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.terminal, color: Color(0xFF38BDF8), size: 14),
              SizedBox(width: 6),
              Text(
                'AUTONOMOUS AGENT EXECUTION TRACE',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...steps.map((step) {
            IconData iconData;
            Color iconColor;
            switch (step.status) {
              case 'success':
                iconData = Icons.check_circle_rounded;
                iconColor = primaryEmerald;
                break;
              case 'failed':
                iconData = Icons.error_outline_rounded;
                iconColor = Colors.redAccent;
                break;
              case 'pending_approval':
                iconData = Icons.shield_outlined;
                iconColor = amberAlert;
                break;
              default:
                iconData = Icons.play_arrow_rounded;
                iconColor = neonCyan;
                break;
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(iconData, color: iconColor, size: 13),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      step.stepName,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: step.status == 'failed'
                            ? Colors.red.shade300
                            : const Color(0xFFE2E8F0),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble() {
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
              style: TextStyle(fontSize: 12, color: Color(0xFFE2E8F0)),
            ),
          ],
        ),
      ),
    );
  }
}
