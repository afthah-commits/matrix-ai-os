import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/presentation/widgets/matrix_logo_widget.dart';
import 'package:matrix_ai_os/core/utils/formatters.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/proactive_context_engine.dart';
import 'package:matrix_ai_os/features/ai_brain/presentation/providers/ai_brain_providers.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/controllers/dashboard_controller.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/services/wake_word_bridge_service.dart';
import 'package:matrix_ai_os/features/device_ingestion/presentation/providers/device_ingestion_providers.dart';
import 'package:matrix_ai_os/features/ocr_vision/presentation/providers/ocr_vision_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> with WidgetsBindingObserver {
  bool _overlayGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverlayPermission());
  }

  Future<void> _checkOverlayPermission() async {
    final granted =
        await ref.read(wakeWordBridgeServiceProvider).isOverlayPermissionGranted();
    if (mounted) {
      setState(() {
        _overlayGranted = granted;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(deviceIngestionControllerProvider.notifier).checkPermissions();
      ref.invalidate(accessibilityEnabledProvider);
      ref.read(dashboardControllerProvider.notifier).refreshMetrics();
      _checkOverlayPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardControllerProvider);
    final controller = ref.read(dashboardControllerProvider.notifier);

    final permState = ref.watch(deviceIngestionControllerProvider);
    final permController = ref.read(deviceIngestionControllerProvider.notifier);

    const primaryEmerald = Color(0xFF10B981);
    const neonCyan = Color(0xFF06B6D4);
    const accentViolet = Color(0xFF8B5CF6);
    const amberAlert = Color(0xFFF59E0B);
    const surfaceCardColor = Color(0xFF111827);
    const borderColor = Color(0xFF1F2937);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
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
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Privacy-First Local AI Core',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: primaryEmerald.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primaryEmerald.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_rounded, color: primaryEmerald, size: 14),
                const SizedBox(width: 4),
                Text(
                  'v${AppConstants.appVersion}',
                  style: const TextStyle(
                    color: primaryEmerald,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: state.isLoading && !state.isInitialized
          ? const Center(
              child: CircularProgressIndicator(color: primaryEmerald),
            )
          : RefreshIndicator(
              color: primaryEmerald,
              onRefresh: () async {
                await controller.refreshMetrics();
                await permController.checkPermissions();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // System Banner
                    _buildSystemBanner(primaryEmerald),
                    const SizedBox(height: 16),

                    // Proactive Context Insights
                    _buildProactiveInsightsSection(
                      ref,
                      surfaceCardColor,
                      borderColor,
                      primaryEmerald,
                      neonCyan,
                      amberAlert,
                    ),

                    // Row 1: Encryption & Storage Size
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            title: 'ENCRYPTION',
                            value: state.encryptionStatus,
                            subtitle: 'AES-256-GCM Keystore',
                            icon: Icons.lock_outline,
                            accentColor: primaryEmerald,
                            surfaceColor: surfaceCardColor,
                            borderColor: borderColor,
                            isBadge: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'LOCAL DB SIZE',
                            value: Formatters.formatBytes(state.dbSizeBytes),
                            subtitle: 'Budget: < 30 MB',
                            icon: Icons.storage_rounded,
                            accentColor: neonCyan,
                            surfaceColor: surfaceCardColor,
                            borderColor: borderColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Row 2: Memory Nodes & Daily Summaries
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            title: 'MEMORY NODES',
                            value: state.totalMemoryNodes.toString(),
                            subtitle: 'Encrypted atomic logs',
                            icon: Icons.psychology_outlined,
                            accentColor: accentViolet,
                            surfaceColor: surfaceCardColor,
                            borderColor: borderColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'DAILY SUMMARIES',
                            value: state.totalDailySummaries.toString(),
                            subtitle: 'Pruned 30-day archives',
                            icon: Icons.auto_graph_rounded,
                            accentColor: amberAlert,
                            surfaceColor: surfaceCardColor,
                            borderColor: borderColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Row 3: OCR Docs & Knowledge Graph Links (Phase 3 Core)
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            title: 'INDEXED OCR DOCS',
                            value: state.ocrDocCount.toString(),
                            subtitle: 'Immune from pruning',
                            icon: Icons.document_scanner_rounded,
                            accentColor: const Color(0xFFC084FC),
                            surfaceColor: surfaceCardColor,
                            borderColor: borderColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'KNOWLEDGE GRAPH',
                            value: state.knowledgeEdgeCount.toString(),
                            subtitle: 'Semantic connections',
                            icon: Icons.hub_rounded,
                            accentColor: const Color(0xFF34D399),
                            surfaceColor: surfaceCardColor,
                            borderColor: borderColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Category Breakdown Chips
                    _buildCategoryBreakdown(state, surfaceCardColor, borderColor),
                    const SizedBox(height: 20),

                    // Device Sensors & Ingestion Permissions Card
                    _buildPermissionsCard(
                      permState: permState,
                      permController: permController,
                      isAccessibilityGranted:
                          ref.watch(accessibilityEnabledProvider).value ?? false,
                      onOpenAccessibility: () => ref
                          .read(actionDispatcherServiceProvider)
                          .openAccessibilitySettings(),
                      wakeWordBridge: ref.watch(wakeWordBridgeServiceProvider),
                      isOverlayGranted: _overlayGranted,
                      surfaceColor: surfaceCardColor,
                      borderColor: borderColor,
                      emerald: primaryEmerald,
                      cyan: neonCyan,
                      violet: accentViolet,
                    ),
                    const SizedBox(height: 20),

                    // Ingestion & Action Controls
                    const Text(
                      'AI VISION & PIPELINE CONTROLS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Phase 3 Ingestion Action: Index Gallery OCR
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentViolet,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 2,
                            ),
                            onPressed: state.isLoading || permState.isSyncing
                                ? null
                                : () async {
                                    await controller.indexGalleryOcr(
                                      ocrService: ref.read(galleryOcrServiceProvider),
                                      kgService: ref.read(knowledgeGraphServiceProvider),
                                    );
                                    await permController.checkPermissions();
                                  },
                            icon: const Icon(Icons.document_scanner_rounded, size: 18),
                            label: const Text(
                              'Index Gallery OCR',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: neonCyan,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 2,
                            ),
                            onPressed: state.isLoading || permState.isSyncing
                                ? null
                                : () async {
                                    await controller.syncDeviceData(
                                      usageService: ref.read(usageIngestionServiceProvider),
                                      callLogService: ref.read(callLogIngestionServiceProvider),
                                      notifHandler: ref.read(notificationIngestionHandlerProvider),
                                      kgService: ref.read(knowledgeGraphServiceProvider),
                                    );
                                    await permController.checkPermissions();
                                  },
                            icon: const Icon(Icons.sync_rounded, size: 18),
                            label: const Text(
                              'Sync Sensors Now',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryEmerald,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: state.isLoading
                                ? null
                                : () => controller.testWriteAndEncrypt(
                                      kgService: ref.read(knowledgeGraphServiceProvider),
                                    ),
                            icon: const Icon(Icons.enhanced_encryption, size: 16),
                            label: const Text(
                              'Test Write & Encrypt',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: amberAlert,
                              side: BorderSide(color: amberAlert.withValues(alpha: 0.7)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: state.isLoading
                                ? null
                                : () => controller.simulateRetentionAndPrune(),
                            icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                            label: const Text(
                              'Simulate & Prune',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Cipher Inspection / Zero Data Leakage Proof
                    if (state.lastTestRawCiphertext != null) ...[
                      _buildCipherInspector(
                        rawCiphertext: state.lastTestRawCiphertext!,
                        decryptedText: state.lastTestDecryptedText ?? '',
                        surfaceColor: surfaceCardColor,
                        borderColor: borderColor,
                        emerald: primaryEmerald,
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Terminal Operation Log
                    _buildConsoleAuditLog(
                      logs: state.operationLogs,
                      surfaceColor: const Color(0xFF070B14),
                      borderColor: borderColor,
                    ),
                    const SizedBox(height: 20),

                    // Production Release Footer
                    _buildReleaseFooter(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSystemBanner(Color primaryEmerald) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131D2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_rounded, color: primaryEmerald, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Zero Image Duplication & Zero Leakage',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Gallery OCR extracts text in-memory. Only metadata is encrypted & linked to Knowledge Graph.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(
    DashboardState state,
    Color surfaceColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildCategoryPill('Screen Time', state.screenTimeCount, const Color(0xFF06B6D4)),
          _buildCategoryPill('Call Logs', state.callLogCount, const Color(0xFF8B5CF6)),
          _buildCategoryPill('Transactions', state.transactionCount, const Color(0xFF10B981)),
          _buildCategoryPill('OCR Docs', state.ocrDocCount, const Color(0xFFC084FC)),
          _buildCategoryPill('Alerts/Notes', state.noteCount, const Color(0xFFF59E0B)),
        ],
      ),
    );
  }

  Widget _buildCategoryPill(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 9.5),
        ),
      ],
    );
  }

  Widget _buildProactiveInsightsSection(
    WidgetRef ref,
    Color surfaceColor,
    Color borderColor,
    Color emerald,
    Color cyan,
    Color amber,
  ) {
    final insightsAsync = ref.watch(proactiveInsightsProvider);

    return insightsAsync.when(
      data: (insights) {
        if (insights.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: amber, size: 16),
                const SizedBox(width: 6),
                const Text(
                  'PROACTIVE CONTEXT INSIGHTS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...insights.map((insight) {
              final color = insight.type == InsightType.spendingSpike
                  ? Colors.redAccent
                  : insight.type == InsightType.screenTimeNudge
                      ? amber
                      : cyan;
              final icon = insight.type == InsightType.spendingSpike
                  ? Icons.trending_up
                  : insight.type == InsightType.screenTimeNudge
                      ? Icons.timer
                      : Icons.flight_takeoff;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: color, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            insight.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            insight.message,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
    );
  }

  Widget _buildPermissionsCard({
    required DevicePermissionsState permState,
    required DeviceIngestionController permController,
    required bool isAccessibilityGranted,
    required VoidCallback onOpenAccessibility,
    required WakeWordBridgeService wakeWordBridge,
    required bool isOverlayGranted,
    required Color surfaceColor,
    required Color borderColor,
    required Color emerald,
    required Color cyan,
    required Color violet,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.health_and_safety_rounded, color: Color(0xFF06B6D4), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'PERMISSION DOCTOR (SYSTEM WIZARD)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: Colors.grey),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  permController.checkPermissions();
                  ref.invalidate(accessibilityEnabledProvider);
                },
                tooltip: 'Refresh permission states',
              ),
            ],
          ),
          const Divider(color: Color(0xFF1F2937), height: 16),

          // 1. Microphone Permission (Voice Assistant)
          _buildPermissionRow(
            title: 'Microphone (Voice Assistant)',
            isGranted: permState.microphoneGranted,
            onAction: () => permController.requestMicrophonePermission(),
            actionLabel: 'Grant',
            emerald: emerald,
          ),
          const SizedBox(height: 8),

          // 2. All Files Access Permission (PDF & Document Finder)
          _buildPermissionRow(
            title: 'All Files Access (PDF & Passport Finder)',
            isGranted: permState.allFilesGranted,
            onAction: () => permController.openAllFilesSettings(),
            actionLabel: 'Settings',
            emerald: emerald,
          ),
          const SizedBox(height: 8),

          // 3. Usage Stats Permission
          _buildPermissionRow(
            title: 'Usage Access (Screen Time)',
            isGranted: permState.usageStatsGranted,
            onAction: () => permController.openUsageAccessSettings(),
            actionLabel: 'Settings',
            emerald: emerald,
          ),
          const SizedBox(height: 8),

          // 4. Notification Listener Permission
          _buildPermissionRow(
            title: 'Notification Access (Bank Alerts)',
            isGranted: permState.notificationListenerGranted,
            onAction: () => permController.openNotificationListenerSettings(),
            actionLabel: 'Settings',
            emerald: emerald,
          ),
          const SizedBox(height: 8),

          // 5. Call Log Permission
          _buildPermissionRow(
            title: 'Call Logs (Telephony Stream)',
            isGranted: permState.callLogGranted,
            onAction: () => permController.requestCallLogPermission(),
            actionLabel: 'Grant',
            emerald: emerald,
          ),
          const SizedBox(height: 8),

          // 6. Gallery Permission (Phase 3 Vision OCR)
          _buildPermissionRow(
            title: 'Gallery / Photos (Visual OCR)',
            isGranted: permState.galleryPermissionGranted,
            onAction: () => permController.requestGalleryPermission(),
            actionLabel: 'Grant',
            emerald: emerald,
          ),
          const SizedBox(height: 8),

          // 7. Accessibility Service Permission (Phase 5 Action & Screen Context)
          _buildPermissionRow(
            title: 'Accessibility (Action & Screen Reader)',
            isGranted: isAccessibilityGranted,
            onAction: onOpenAccessibility,
            actionLabel: 'Settings',
            emerald: emerald,
          ),
          const SizedBox(height: 8),

          // 8. Hands-Free "Hey Matrix" Wake Word Service
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: wakeWordBridge.isServiceRunning ? emerald : Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Hands-Free "Hey Matrix" Wake Word',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: wakeWordBridge.isServiceRunning,
                    activeThumbColor: emerald,
                    onChanged: (enabled) async {
                      if (enabled) {
                        await wakeWordBridge.startWakeWordService();
                      } else {
                        await wakeWordBridge.stopWakeWordService();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 9. Android Default Digital Assistant (System Assist Settings)
          _buildPermissionRow(
            title: 'Default Assistant (Long-Press Power)',
            isGranted: false,
            onAction: () => wakeWordBridge.openDefaultAssistantSettings(),
            actionLabel: 'Settings',
            emerald: emerald,
          ),
          const SizedBox(height: 8),

          // 10. Floating Pop-Up Overlay (Siri-Style)
          _buildPermissionRow(
            title: 'Floating Pop-Up Overlay (Siri-Style)',
            isGranted: isOverlayGranted,
            onAction: () => wakeWordBridge.openOverlayPermissionSettings(),
            actionLabel: 'Settings',
            emerald: emerald,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionRow({
    required String title,
    required bool isGranted,
    required VoidCallback onAction,
    required String actionLabel,
    required Color emerald,
  }) {
    return InkWell(
      onTap: isGranted ? null : onAction,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isGranted ? emerald : Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
            if (isGranted)
              Row(
                children: [
                  Icon(Icons.check_circle, color: emerald, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Active',
                    style: TextStyle(color: emerald, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              )
            else
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFF38BDF8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: onAction,
                child: Text(actionLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color surfaceColor,
    required Color borderColor,
    bool isBadge = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              Icon(icon, color: accentColor, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          if (isBadge)
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          else
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCipherInspector({
    required String rawCiphertext,
    required String decryptedText,
    required Color surfaceColor,
    required Color borderColor,
    required Color emerald,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: emerald.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user, color: emerald, size: 16),
              const SizedBox(width: 8),
              const Text(
                'LIVE CIPHER & STORAGE VERIFICATION',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF1F2937), height: 18),
          const Text(
            'RAW CIPHERTEXT STORED ON DISK (OBJECTBOX):',
            style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              rawCiphertext,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Color(0xFF38BDF8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'DECRYPTED RUNTIME VERIFICATION:',
            style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              decryptedText,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF34D399),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsoleAuditLog({
    required List<String> logs,
    required Color surfaceColor,
    required Color borderColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.terminal, color: Colors.greenAccent, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'SECURITY & SENSOR AUDIT LOG',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF1F2937), height: 18),
          if (logs.isEmpty)
            const Text(
              'No audit entries recorded yet.',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[logs.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text(
                    log,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildReleaseFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, size: 14, color: Color(0xFF10B981)),
              const SizedBox(width: 6),
              Text(
                '${AppConstants.appName} v${AppConstants.appVersion}',
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'RELEASE',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '100% Privacy-First • Hardware AES-256-GCM • Air-Gapped Local Core • <30MB Footprint',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 10,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
