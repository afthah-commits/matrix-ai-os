import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/utils/formatters.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/controllers/dashboard_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardControllerProvider);
    final controller = ref.read(dashboardControllerProvider.notifier);

    const primaryEmerald = Color(0xFF10B981);
    const neonCyan = Color(0xFF06B6D4);
    const accentViolet = Color(0xFF8B5CF6);
    const surfaceCardColor = Color(0xFF111827);
    const borderColor = Color(0xFF1F2937);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
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
              child: Icon(Icons.security, color: primaryEmerald, size: 20),
            ),
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
              color: neonCyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: neonCyan.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, color: neonCyan, size: 14),
                const SizedBox(width: 4),
                Text(
                  'PHASE 1.1',
                  style: TextStyle(
                    color: neonCyan,
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
              child: CircularProgressIndicator(color: Color(0xFF10B981)),
            )
          : RefreshIndicator(
              color: primaryEmerald,
              onRefresh: () => controller.refreshMetrics(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // System Banner
                    _buildSystemBanner(primaryEmerald),
                    const SizedBox(height: 16),

                    // Metrics Grid
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
                            subtitle: 'Target: < 30 MB budget',
                            icon: Icons.storage_rounded,
                            accentColor: neonCyan,
                            surfaceColor: surfaceCardColor,
                            borderColor: borderColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            title: 'MEMORY NODES',
                            value: state.totalMemoryNodes.toString(),
                            subtitle: 'Atomic encrypted logs',
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
                            subtitle: 'Aggregated & pruned',
                            icon: Icons.auto_graph_rounded,
                            accentColor: Colors.amber,
                            surfaceColor: surfaceCardColor,
                            borderColor: borderColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Action Controls
                    const Text(
                      'CORE SYSTEM ACTIONS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryEmerald,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 2,
                            ),
                            onPressed: state.isLoading
                                ? null
                                : () => controller.testWriteAndEncrypt(),
                            icon: state.isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Icon(Icons.enhanced_encryption, size: 18),
                            label: const Text(
                              'Test Write & Encrypt',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: neonCyan,
                              side: BorderSide(color: neonCyan.withValues(alpha: 0.7)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: state.isLoading
                                ? null
                                : () => controller.simulateRetentionAndPrune(),
                            icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                            label: const Text(
                              'Simulate & Prune',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
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
                  'Zero Cloud Leakage Guarantee',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'All telemetry, notes, and memory nodes are encrypted locally with hardware-backed keys.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
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
                    'SECURITY & STORAGE AUDIT LOG',
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
