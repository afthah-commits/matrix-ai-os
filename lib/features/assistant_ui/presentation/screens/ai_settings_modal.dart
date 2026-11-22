import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/byok_key_manager.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/offline_slm_manager.dart';
import 'package:matrix_ai_os/features/ai_brain/presentation/providers/ai_brain_providers.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/controllers/chat_controller.dart';

/// Modal bottom sheet allowing users to securely configure BYOK API keys,
/// manage optional on-demand offline SLM models, and toggle MCP plugins.
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
    const accentViolet = Color(0xFF8B5CF6);
    const surfaceCard = Color(0xFF111827);
    const bgContainer = Color(0xFF0F172A);
    const borderColor = Color(0xFF1F2937);

    final slmManager = ref.watch(offlineSlmManagerProvider);
    final mcpRegistry = ref.watch(mcpPluginRegistryProvider);
    final wakeWordBridge = ref.watch(wakeWordBridgeServiceProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
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
                            'AI Brain, SLM & MCP Settings',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '100% Free • Zero Cloud Lock-in • Edge Models',
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

                  // 1. Air-Gapped Offline Mode Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isOfflineOnly ? primaryEmerald : borderColor,
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
                                'Blocks all network calls. Runs on-device via local encrypted memory & edge SLMs.',
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
                  const SizedBox(height: 20),

                  // 2. Active MCP Plugins Section
                  Row(
                    children: const [
                      Icon(Icons.extension_outlined, color: primaryEmerald, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'ACTIVE MCP PLUGINS (EXTENSIONS)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: primaryEmerald,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      children: mcpRegistry.getAllPlugins().map((plugin) {
                        final isEnabled = mcpRegistry.isPluginEnabled(plugin.id);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      plugin.name,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      plugin.description,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white60,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: isEnabled,
                                activeThumbColor: primaryEmerald,
                                activeTrackColor: primaryEmerald.withValues(alpha: 0.3),
                                onChanged: (val) {
                                  mcpRegistry.setPluginEnabled(plugin.id, val);
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Offline Edge SLMs (Optional On-Demand)
                  Row(
                    children: const [
                      Icon(Icons.memory_outlined, color: accentViolet, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'OFFLINE EDGE SLM MODELS (OPTIONAL)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: accentViolet,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Zero weights bundled in APK (<30MB target). Download on-demand for offline neural reasoning.',
                    style: TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                  const SizedBox(height: 8),

                  ...OfflineSlmManager.catalog.map((model) {
                    final state = slmManager.getModelState(model.id);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: surfaceCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                model.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accentViolet.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  model.sizeFormatted,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: accentViolet,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            model.description,
                            style: const TextStyle(fontSize: 10, color: Colors.white60),
                          ),
                          const SizedBox(height: 8),

                          if (state.status == SlmStatus.downloaded)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.check_circle, color: primaryEmerald, size: 14),
                                    SizedBox(width: 4),
                                    Text('Installed & Ready', style: TextStyle(fontSize: 11, color: primaryEmerald)),
                                  ],
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
                                  label: const Text('Free Space', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                                  onPressed: () async {
                                    await slmManager.deleteModel(model.id);
                                  },
                                ),
                              ],
                            )
                          else if (state.status == SlmStatus.downloading)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LinearProgressIndicator(
                                  value: state.progress,
                                  color: accentViolet,
                                  backgroundColor: Colors.white10,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Downloading ${(state.progress * 100).toInt()}%',
                                      style: const TextStyle(fontSize: 10, color: Colors.white60),
                                    ),
                                    TextButton(
                                      onPressed: () => slmManager.cancelDownload(model.id),
                                      child: const Text('Cancel', style: TextStyle(fontSize: 10, color: Colors.redAccent)),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          else
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.download_rounded, size: 14, color: accentViolet),
                                label: const Text('Download Model', style: TextStyle(fontSize: 11, color: accentViolet)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: accentViolet),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                ),
                                onPressed: () {
                                  slmManager.downloadModel(model);
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 20),

                  // 4. Hands-Free Wake Word & Android Default Assistant
                  Row(
                    children: const [
                      Icon(Icons.mic_none_rounded, color: neonCyan, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'HANDS-FREE WAKE WORD & DIGITAL ASSISTANT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: neonCyan,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: surfaceCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '"Hey Matrix" Wake Word',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  wakeWordBridge.isServiceRunning
                                      ? 'Active: listening in background'
                                      : 'Disabled: tap switch to activate',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: wakeWordBridge.isServiceRunning
                                        ? primaryEmerald
                                        : Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                            Switch(
                              value: wakeWordBridge.isServiceRunning,
                              activeThumbColor: primaryEmerald,
                              onChanged: (val) async {
                                if (val) {
                                  await wakeWordBridge.startWakeWordService();
                                } else {
                                  await wakeWordBridge.stopWakeWordService();
                                }
                              },
                            ),
                          ],
                        ),
                        const Divider(color: borderColor, height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Default Digital Assistant',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Trigger via long-press Power / Home button',
                                  style: TextStyle(fontSize: 11, color: Colors.white54),
                                ),
                              ],
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: neonCyan,
                                side: const BorderSide(color: neonCyan),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => wakeWordBridge.openDefaultAssistantSettings(),
                              child: const Text('Configure', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (!_isOfflineOnly) ...[
                    // Provider Selector
                    const Text(
                      'ACTIVE CLOUD AI PROVIDER',
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
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureGeminiKey ? Icons.visibility_off : Icons.visibility,
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
                              _obscureOpenAiKey ? Icons.visibility_off : Icons.visibility,
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
