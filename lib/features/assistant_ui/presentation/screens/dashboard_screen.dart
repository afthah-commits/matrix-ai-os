import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/presentation/widgets/matrix_logo_widget.dart';
import 'package:matrix_ai_os/core/utils/formatters.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/proactive_context_engine.dart';
import 'package:matrix_ai_os/features/ai_brain/presentation/providers/ai_brain_providers.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/controllers/dashboard_controller.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/screens/memory_category_detail_screen.dart';
import 'package:matrix_ai_os/features/device_ingestion/presentation/providers/device_ingestion_providers.dart';
import 'package:matrix_ai_os/features/ocr_vision/presentation/providers/ocr_vision_providers.dart';
import 'package:matrix_ai_os/features/ocr_vision/presentation/screens/upload_document_modal.dart';

// Palette constants
const _primaryEmerald = Color(0xFF10B981);
const _neonCyan = Color(0xFF06B6D4);
const _accentViolet = Color(0xFF8B5CF6);
const _amberAlert = Color(0xFFF59E0B);
const _surfaceCardColor = Color(0xFF111827);
const _borderColor = Color(0xFF1F2937);

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
              color: _primaryEmerald.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _primaryEmerald.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_rounded, color: _primaryEmerald, size: 14),
                const SizedBox(width: 4),
                Text(
                  'v${AppConstants.appVersion}',
                  style: const TextStyle(
                    color: _primaryEmerald,
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
      body: RefreshIndicator(
        color: _primaryEmerald,
        onRefresh: () async {
          await ref.read(dashboardControllerProvider.notifier).refreshMetrics();
          await ref.read(deviceIngestionControllerProvider.notifier).checkPermissions();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const RepaintBoundary(child: _SystemBannerWidget()),
                  const SizedBox(height: 16),
                  const RepaintBoundary(child: _ProactiveInsightsSection()),
                  const RepaintBoundary(child: _MetricCardsSection()),
                  const SizedBox(height: 12),
                  const RepaintBoundary(child: _CategoryBreakdownSection()),
                  const SizedBox(height: 20),
                  RepaintBoundary(
                    child: _PermissionsSection(isOverlayGranted: _overlayGranted),
                  ),
                  const SizedBox(height: 20),
                  const RepaintBoundary(child: _PipelineControlsSection()),
                  const SizedBox(height: 20),
                  const RepaintBoundary(child: _CipherInspectorSection()),
                  const RepaintBoundary(child: _ConsoleAuditLogSection()),
                  const SizedBox(height: 20),
                  const RepaintBoundary(child: _ReleaseFooterWidget()),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. System Banner
// ---------------------------------------------------------------------------
class _SystemBannerWidget extends StatelessWidget {
  const _SystemBannerWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131D2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: const [
          Icon(Icons.shield_rounded, color: _primaryEmerald, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
}

// ---------------------------------------------------------------------------
// 2. Proactive Insights Section
// ---------------------------------------------------------------------------
class _ProactiveInsightsSection extends ConsumerWidget {
  const _ProactiveInsightsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(proactiveInsightsProvider);

    return insightsAsync.when(
      data: (insights) {
        if (insights.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.bolt, color: _amberAlert, size: 16),
                SizedBox(width: 6),
                Text(
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
                      ? _amberAlert
                      : _neonCyan;
              final icon = insight.type == InsightType.spendingSpike
                  ? Icons.trending_up
                  : insight.type == InsightType.screenTimeNudge
                      ? Icons.timer
                      : Icons.flight_takeoff;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _surfaceCardColor,
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
}

// ---------------------------------------------------------------------------
// 3. Metric Cards Section (Riverpod .select for isolated rebuilds)
// ---------------------------------------------------------------------------
class _MetricCardsSection extends ConsumerWidget {
  const _MetricCardsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final encryptionStatus =
        ref.watch(dashboardControllerProvider.select((s) => s.encryptionStatus));
    final dbSizeBytes =
        ref.watch(dashboardControllerProvider.select((s) => s.dbSizeBytes));
    final totalMemoryNodes =
        ref.watch(dashboardControllerProvider.select((s) => s.totalMemoryNodes));
    final totalDailySummaries =
        ref.watch(dashboardControllerProvider.select((s) => s.totalDailySummaries));
    final ocrDocCount =
        ref.watch(dashboardControllerProvider.select((s) => s.ocrDocCount));
    final knowledgeEdgeCount =
        ref.watch(dashboardControllerProvider.select((s) => s.knowledgeEdgeCount));

    return Column(
      children: [
        // Row 1: Encryption & Storage Size
        Row(
          children: [
            Expanded(
              child: _MetricCardItem(
                title: 'ENCRYPTION',
                value: encryptionStatus,
                subtitle: 'AES-256-GCM Keystore',
                icon: Icons.lock_outline,
                accentColor: _primaryEmerald,
                isBadge: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCardItem(
                title: 'LOCAL DB SIZE',
                value: Formatters.formatBytes(dbSizeBytes),
                subtitle: 'Budget: < 30 MB',
                icon: Icons.storage_rounded,
                accentColor: _neonCyan,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Row 2: Memory Nodes & Daily Summaries
        Row(
          children: [
            Expanded(
              child: _MetricCardItem(
                title: 'MEMORY NODES',
                value: totalMemoryNodes.toString(),
                subtitle: 'Encrypted atomic logs',
                icon: Icons.psychology_outlined,
                accentColor: _accentViolet,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MemoryCategoryDetailScreen(initialCategory: 'all'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCardItem(
                title: 'DAILY SUMMARIES',
                value: totalDailySummaries.toString(),
                subtitle: 'Pruned 30-day archives',
                icon: Icons.auto_graph_rounded,
                accentColor: _amberAlert,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MemoryCategoryDetailScreen(initialCategory: 'daily_summary'),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Row 3: OCR Docs & Knowledge Graph Links
        Row(
          children: [
            Expanded(
              child: _MetricCardItem(
                title: 'INDEXED OCR DOCS',
                value: ocrDocCount.toString(),
                subtitle: 'Immune from pruning',
                icon: Icons.document_scanner_rounded,
                accentColor: const Color(0xFFC084FC),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MemoryCategoryDetailScreen(initialCategory: 'ocr_doc'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCardItem(
                title: 'KNOWLEDGE GRAPH',
                value: knowledgeEdgeCount.toString(),
                subtitle: 'Semantic connections',
                icon: Icons.hub_rounded,
                accentColor: const Color(0xFF34D399),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MemoryCategoryDetailScreen(initialCategory: 'all'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Category Breakdown Section (Riverpod .select for isolated rebuilds)
// ---------------------------------------------------------------------------
class _CategoryBreakdownSection extends ConsumerWidget {
  const _CategoryBreakdownSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenTime =
        ref.watch(dashboardControllerProvider.select((s) => s.screenTimeCount));
    final callLogs =
        ref.watch(dashboardControllerProvider.select((s) => s.callLogCount));
    final transactions =
        ref.watch(dashboardControllerProvider.select((s) => s.transactionCount));
    final ocrDocs =
        ref.watch(dashboardControllerProvider.select((s) => s.ocrDocCount));
    final notes =
        ref.watch(dashboardControllerProvider.select((s) => s.noteCount));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: _surfaceCardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildCategoryPill(
            'Screen Time',
            screenTime,
            const Color(0xFF06B6D4),
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MemoryCategoryDetailScreen(initialCategory: 'screen_time'),
              ),
            ),
          ),
          _buildCategoryPill(
            'Call Logs',
            callLogs,
            const Color(0xFF8B5CF6),
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MemoryCategoryDetailScreen(initialCategory: 'call_log'),
              ),
            ),
          ),
          _buildCategoryPill(
            'Transactions',
            transactions,
            const Color(0xFF10B981),
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MemoryCategoryDetailScreen(initialCategory: 'transaction'),
              ),
            ),
          ),
          _buildCategoryPill(
            'OCR Docs',
            ocrDocs,
            const Color(0xFFC084FC),
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MemoryCategoryDetailScreen(initialCategory: 'ocr_doc'),
              ),
            ),
          ),
          _buildCategoryPill(
            'Alerts/Notes',
            notes,
            const Color(0xFFF59E0B),
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MemoryCategoryDetailScreen(initialCategory: 'system_note'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPill(String label, int count, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Permissions Doctor Card
// ---------------------------------------------------------------------------
class _PermissionsSection extends ConsumerWidget {
  final bool isOverlayGranted;

  const _PermissionsSection({required this.isOverlayGranted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permState = ref.watch(deviceIngestionControllerProvider);
    final permController = ref.read(deviceIngestionControllerProvider.notifier);
    final isAccessibilityGranted =
        ref.watch(accessibilityEnabledProvider).value ?? false;
    final wakeWordBridge = ref.watch(wakeWordBridgeServiceProvider);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceCardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
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
          ),
          const SizedBox(height: 8),

          // 2. All Files Access Permission (PDF & Document Finder)
          _buildPermissionRow(
            title: 'All Files Access (PDF & Passport Finder)',
            isGranted: permState.allFilesGranted,
            onAction: () => permController.openAllFilesSettings(),
            actionLabel: 'Settings',
          ),
          const SizedBox(height: 8),

          // 3. Usage Stats Permission
          _buildPermissionRow(
            title: 'Usage Access (Screen Time)',
            isGranted: permState.usageStatsGranted,
            onAction: () => permController.openUsageAccessSettings(),
            actionLabel: 'Settings',
          ),
          const SizedBox(height: 8),

          // 4. Notification Listener Permission
          _buildPermissionRow(
            title: 'Notification Access (Bank Alerts)',
            isGranted: permState.notificationListenerGranted,
            onAction: () => permController.openNotificationListenerSettings(),
            actionLabel: 'Settings',
          ),
          const SizedBox(height: 8),

          // 5. Call Log Permission
          _buildPermissionRow(
            title: 'Call Logs (Telephony Stream)',
            isGranted: permState.callLogGranted,
            onAction: () => permController.requestCallLogPermission(),
            actionLabel: 'Grant',
          ),
          const SizedBox(height: 8),

          // 6. Gallery Permission (Phase 3 Vision OCR)
          _buildPermissionRow(
            title: 'Gallery / Photos (Visual OCR)',
            isGranted: permState.galleryPermissionGranted,
            onAction: () => permController.requestGalleryPermission(),
            actionLabel: 'Grant',
          ),
          const SizedBox(height: 8),

          // 7. Accessibility Service Permission (Phase 5 Action & Screen Context)
          _buildPermissionRow(
            title: 'Accessibility (Action & Screen Reader)',
            isGranted: isAccessibilityGranted,
            onAction: () => ref.read(actionDispatcherServiceProvider).openAccessibilitySettings(),
            actionLabel: 'Settings',
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
                        color: wakeWordBridge.isServiceRunning ? _primaryEmerald : Colors.redAccent,
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
                    activeThumbColor: _primaryEmerald,
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
          ),
          const SizedBox(height: 8),

          // 10. Floating Pop-Up Overlay (Siri-Style)
          _buildPermissionRow(
            title: 'Floating Pop-Up Overlay (Siri-Style)',
            isGranted: isOverlayGranted,
            onAction: () => wakeWordBridge.openOverlayPermissionSettings(),
            actionLabel: 'Settings',
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
                    color: isGranted ? _primaryEmerald : Colors.redAccent,
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
                children: const [
                  Icon(Icons.check_circle, color: _primaryEmerald, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Active',
                    style: TextStyle(color: _primaryEmerald, fontSize: 11, fontWeight: FontWeight.w600),
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
}

// ---------------------------------------------------------------------------
// 6. Pipeline Controls Section (Riverpod .select for isolated rebuilds)
// ---------------------------------------------------------------------------
class _PipelineControlsSection extends ConsumerWidget {
  const _PipelineControlsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading =
        ref.watch(dashboardControllerProvider.select((s) => s.isLoading));
    final isSyncing =
        ref.watch(deviceIngestionControllerProvider.select((p) => p.isSyncing));
    final controller = ref.read(dashboardControllerProvider.notifier);
    final permController = ref.read(deviceIngestionControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

        // 4 Intuitive Pipeline Action Cards (2x2 Grid)
        Row(
          children: [
            Expanded(
              child: _PipelineActionCardItem(
                title: 'Sync Phone Signals',
                subtitle: 'Fetch screen time, call logs & bank alerts',
                icon: Icons.sync_rounded,
                accentColor: _neonCyan,
                isLoading: isLoading || isSyncing,
                onTap: () async {
                  await controller.syncDeviceData(
                    usageService: ref.read(usageIngestionServiceProvider),
                    callLogService: ref.read(callLogIngestionServiceProvider),
                    notifHandler: ref.read(notificationIngestionHandlerProvider),
                    kgService: ref.read(knowledgeGraphServiceProvider),
                  );
                  await permController.checkPermissions();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PipelineActionCardItem(
                title: 'Scan Gallery for Docs',
                subtitle: 'Auto-detect receipts, tickets & IDs',
                icon: Icons.document_scanner_rounded,
                accentColor: _accentViolet,
                isLoading: isLoading || isSyncing,
                onTap: () async {
                  await controller.indexGalleryOcr(
                    ocrService: ref.read(galleryOcrServiceProvider),
                    kgService: ref.read(knowledgeGraphServiceProvider),
                  );
                  await permController.checkPermissions();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _PipelineActionCardItem(
                title: 'Upload ID / Document',
                subtitle: 'Add Passport, PAN, or PDF to vault',
                icon: Icons.add_photo_alternate_rounded,
                accentColor: _primaryEmerald,
                isLoading: false,
                onTap: () => UploadDocumentModal.show(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PipelineActionCardItem(
                title: 'Run AI Memory Pruning',
                subtitle: 'Compress 30+ day logs & free space',
                icon: Icons.cleaning_services_rounded,
                accentColor: _amberAlert,
                isLoading: isLoading,
                onTap: () => controller.simulateRetentionAndPrune(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Cipher Inspector Section (Riverpod .select for isolated rebuilds)
// ---------------------------------------------------------------------------
class _CipherInspectorSection extends ConsumerWidget {
  const _CipherInspectorSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawCiphertext =
        ref.watch(dashboardControllerProvider.select((s) => s.lastTestRawCiphertext));
    final decryptedText =
        ref.watch(dashboardControllerProvider.select((s) => s.lastTestDecryptedText));

    if (rawCiphertext == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceCardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryEmerald.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.verified_user, color: _primaryEmerald, size: 16),
              SizedBox(width: 8),
              Text(
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
              decryptedText ?? '',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF34D399),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8. Console Audit Log Section (Riverpod .select for isolated rebuilds)
// ---------------------------------------------------------------------------
class _ConsoleAuditLogSection extends ConsumerWidget {
  const _ConsoleAuditLogSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs =
        ref.watch(dashboardControllerProvider.select((s) => s.operationLogs));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF070B14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
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
}

// ---------------------------------------------------------------------------
// 9. Release Footer Widget
// ---------------------------------------------------------------------------
class _ReleaseFooterWidget extends StatelessWidget {
  const _ReleaseFooterWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, size: 14, color: _primaryEmerald),
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
                  color: _primaryEmerald.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'RELEASE',
                  style: TextStyle(
                    color: _primaryEmerald,
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

// ---------------------------------------------------------------------------
// Reusable Sub-Widgets
// ---------------------------------------------------------------------------
class _MetricCardItem extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final bool isBadge;
  final VoidCallback? onTap;

  const _MetricCardItem({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.isBadge = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceCardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
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

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: cardContent,
        ),
      );
    }
    return cardContent;
  }
}

class _PipelineActionCardItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final bool isLoading;
  final VoidCallback onTap;

  const _PipelineActionCardItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _surfaceCardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: accentColor, size: 20),
                  ),
                  const Spacer(),
                  if (isLoading)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accentColor,
                      ),
                    )
                  else
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: accentColor.withValues(alpha: 0.5),
                      size: 12,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 10.5,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
