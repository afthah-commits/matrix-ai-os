import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/byok_key_manager.dart';
import 'package:matrix_ai_os/features/ai_brain/presentation/providers/ai_brain_providers.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/controllers/chat_controller.dart';

/// Modal bottom sheet allowing users to securely configure BYOK API keys,
/// select providers, or enforce 100% Air-Gapped offline mode.
class AiSettingsModal extends ConsumerStatefulWidget {
  const AiSettingsModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AiSettingsModal(),
    );
  }

  @override
  ConsumerState<AiSettingsModal> createState() => _AiSettingsModalState();
}

class _AiSettingsModalState extends ConsumerState<AiSettingsModal> {
  final _geminiKeyController = TextEditingController();
  final _openAiKeyController = TextEditingController();
  final _openAiBaseUrlController = TextEditingController();

  bool _isOfflineOnly = false;
  AiProvider _selectedProvider = AiProvider.gemini;
  bool _obscureGeminiKey = true;
  bool _obscureOpenAiKey = true;
  bool _isLoading = true;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final byok = ref.read(byokKeyManagerProvider);
    final isOffline = await byok.isOfflineOnly();
    final provider = await byok.getSelectedProvider();
    final geminiKey = await byok.getGeminiApiKey();
    final openAiKey = await byok.getOpenAiApiKey();
    final baseUrl = await byok.getOpenAiBaseUrl();

    if (mounted) {
      setState(() {
        _isOfflineOnly = isOffline;
        _selectedProvider = provider;
        _geminiKeyController.text = geminiKey ?? '';
        _openAiKeyController.text = openAiKey ?? '';
        _openAiBaseUrlController.text = baseUrl;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _geminiKeyController.dispose();
    _openAiKeyController.dispose();
    _openAiBaseUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final byok = ref.read(byokKeyManagerProvider);

    await byok.setOfflineOnly(_isOfflineOnly);
    await byok.setSelectedProvider(_selectedProvider);

    if (_geminiKeyController.text.trim().isNotEmpty) {
      await byok.setGeminiApiKey(_geminiKeyController.text.trim());
    }

    if (_openAiKeyController.text.trim().isNotEmpty) {
      await byok.setOpenAiApiKey(_openAiKeyController.text.trim());
    }

    if (_openAiBaseUrlController.text.trim().isNotEmpty) {
      await byok.setOpenAiBaseUrl(_openAiBaseUrlController.text.trim());
    }

    await ref.read(chatControllerProvider.notifier).refreshSettings();

    if (mounted) {
      setState(() {
        _statusMessage = 'Settings saved securely in Android Keystore';
      });

      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  Future<void> _clearAllKeys() async {
    final byok = ref.read(byokKeyManagerProvider);
    await byok.clearAllKeys();
    _geminiKeyController.clear();
    _openAiKeyController.clear();
    await ref.read(chatControllerProvider.notifier).refreshSettings();

    if (mounted) {
      setState(() {
        _statusMessage = 'All stored API keys cleared';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryEmerald = Color(0xFF10B981);
    const neonCyan = Color(0xFF06B6D4);
    const surfaceCard = Color(0xFF111827);
    const bgContainer = Color(0xFF0F172A);
    const borderColor = Color(0xFF1F2937);

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: bgContainer,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: borderColor, width: 1.5),
        ),
      ),
      child: _isLoading
          ? const Center(
              heightFactor: 4,
              child: CircularProgressIndicator(color: primaryEmerald),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryEmerald.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: primaryEmerald.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.tune,
                          color: primaryEmerald,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Brain & BYOK Settings',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '100% Free • Zero Cloud Lock-in • Keystore Encrypted',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Air-Gapped Offline Mode Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isOfflineOnly
                            ? primaryEmerald
                            : borderColor,
                        width: _isOfflineOnly ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: _isOfflineOnly ? primaryEmerald : Colors.white60,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '100% Air-Gapped Offline Mode',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Blocks all network calls. Runs strictly on-device using local encrypted memory.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isOfflineOnly,
                          activeThumbColor: primaryEmerald,
                          activeTrackColor: primaryEmerald.withValues(alpha: 0.3),
                          onChanged: (val) {
                            setState(() {
                              _isOfflineOnly = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  if (!_isOfflineOnly) ...[
                    // Provider Selector
                    const Text(
                      'ACTIVE AI PROVIDER',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: neonCyan,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: surfaceCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<AiProvider>(
                          value: _selectedProvider,
                          isExpanded: true,
                          dropdownColor: surfaceCard,
                          items: AiProvider.values.map((p) {
                            return DropdownMenuItem<AiProvider>(
                              value: p,
                              child: Text(
                                p.displayName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedProvider = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Key Input based on provider
                    if (_selectedProvider == AiProvider.gemini) ...[
                      const Text(
                        'GOOGLE GEMINI API KEY (FREE TIER)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _geminiKeyController,
                        obscureText: _obscureGeminiKey,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Enter AIzaSy... key',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: surfaceCard,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: primaryEmerald),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureGeminiKey
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 18,
                              color: Colors.white54,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureGeminiKey = !_obscureGeminiKey;
                              });
                            },
                          ),
                        ),
                      ),
                    ] else if (_selectedProvider == AiProvider.openAiCompatible) ...[
                      const Text(
                        'OPENAI / CUSTOM COMPATIBLE API KEY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _openAiKeyController,
                        obscureText: _obscureOpenAiKey,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'sk-... key',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: surfaceCard,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: borderColor),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureOpenAiKey
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 18,
                              color: Colors.white54,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureOpenAiKey = !_obscureOpenAiKey;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'CUSTOM BASE URL (Optional for Ollama / Local Proxies)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _openAiBaseUrlController,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'https://api.openai.com/v1',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: surfaceCard,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: borderColor),
                          ),
                        ),
                      ),
                    ],
                  ],

                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryEmerald.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: primaryEmerald.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: primaryEmerald,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: primaryEmerald,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Actions: Save & Clear
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _clearAllKeys,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Clear Keys',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _saveSettings,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryEmerald,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Save Settings',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
