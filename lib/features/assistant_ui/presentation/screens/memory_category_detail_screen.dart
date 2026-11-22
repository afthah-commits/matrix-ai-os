import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/database_providers.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/core/database/models/daily_summary.dart';
import 'package:matrix_ai_os/core/presentation/widgets/matrix_logo_widget.dart';
import 'package:matrix_ai_os/features/ai_brain/presentation/providers/ai_brain_providers.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/controllers/dashboard_controller.dart';
import 'package:matrix_ai_os/features/ocr_vision/presentation/screens/upload_document_modal.dart';

/// Screen displaying decrypted memories for a selected category or all categories
/// with live search, category filtering, delete action, and external file viewer.
class MemoryCategoryDetailScreen extends ConsumerStatefulWidget {
  final String initialCategory;

  const MemoryCategoryDetailScreen({
    super.key,
    this.initialCategory = 'all',
  });

  @override
  ConsumerState<MemoryCategoryDetailScreen> createState() =>
      _MemoryCategoryDetailScreenState();
}

class _MemoryCategoryDetailScreenState
    extends ConsumerState<MemoryCategoryDetailScreen> {
  final TextEditingController _searchController = TextEditingController();
  late String _activeCategory;
  List<DecryptedMemoryNode> _allNodes = [];
  List<DailySummary> _dailySummaries = [];
  bool _isLoading = true;
  String _searchQuery = '';

  static const primaryEmerald = Color(0xFF10B981);
  static const neonCyan = Color(0xFF06B6D4);
  static const amberAlert = Color(0xFFF59E0B);
  static const bgContainer = Color(0xFF090D16);
  static const surfaceCard = Color(0xFF161B22);
  static const borderColor = Color(0xFF30363D);

  static const _filterTabs = [
    {'id': 'all', 'label': 'All Records', 'icon': Icons.all_inclusive},
    {'id': MemoryCategory.ocrDoc, 'label': 'OCR Docs', 'icon': Icons.document_scanner},
    {'id': 'daily_summary', 'label': 'Daily Summaries', 'icon': Icons.auto_graph},
    {'id': MemoryCategory.screenTime, 'label': 'Screen Time', 'icon': Icons.timer},
    {'id': MemoryCategory.callLog, 'label': 'Call Logs', 'icon': Icons.call},
    {'id': MemoryCategory.transaction, 'label': 'Transactions', 'icon': Icons.account_balance_wallet},
    {'id': 'app_usage', 'label': 'App Usages', 'icon': Icons.apps},
    {'id': MemoryCategory.note, 'label': 'Notes & Alerts', 'icon': Icons.note_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _activeCategory = widget.initialCategory;
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _loadMemories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMemories() async {
    setState(() => _isLoading = true);
    final db = ref.read(localDatabaseServiceProvider);

    try {
      final List<DecryptedMemoryNode> nodes;
      if (_activeCategory == 'all' || _activeCategory == 'daily_summary') {
        nodes = await db.getAllDecryptedNodes(limit: 50);
      } else {
        nodes = await db.getDecryptedNodesByCategory(_activeCategory, limit: 50);
      }
      final summaries = db.getAllDailySummaries();

      if (mounted) {
        setState(() {
          _allNodes = nodes;
          _dailySummaries = summaries;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleDeleteNode(DecryptedMemoryNode node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceCard,
        title: const Text('Delete Memory Node?', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Are you sure you want to permanently delete this memory (#${node.id}) from encrypted storage?',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(localDatabaseServiceProvider);
      await db.deleteMemoryNode(node.id);
      await ref.read(dashboardControllerProvider.notifier).refreshMetrics();
      await _loadMemories();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Memory node removed from ObjectBox'),
            backgroundColor: Color(0xFF1F2937),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handleOpenFile(String fileUri, {String? mimeType}) async {
    final actionDispatcher = ref.read(actionDispatcherServiceProvider);
    final res = await actionDispatcher.openFileUri(fileUri, mimeType: mimeType);
    if (res['success'] != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open file: ${res['error'] ?? 'Unknown error'}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  List<DecryptedMemoryNode> _getFilteredNodes() {
    return _allNodes.where((node) {
      // Category filter
      if (_activeCategory != 'all' && node.category != _activeCategory) {
        return false;
      }
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final inContent = node.content.toLowerCase().contains(_searchQuery);
        final inCategory = node.category.toLowerCase().contains(_searchQuery);
        final inMeta = node.metadataJson.toLowerCase().contains(_searchQuery);
        final inUri = (node.fileUri ?? '').toLowerCase().contains(_searchQuery);
        if (!inContent && !inCategory && !inMeta && !inUri) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredNodes = _getFilteredNodes();

    return Scaffold(
      backgroundColor: bgContainer,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            const MatrixLogoWidget(size: 28),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Encrypted Memory Vault',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${_allNodes.length} Decrypted Atomic Logs',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: neonCyan,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Upload Document / ID Card',
            icon: const Icon(Icons.add_photo_alternate_rounded, color: primaryEmerald),
            onPressed: () async {
              await UploadDocumentModal.show(context);
              await _loadMemories();
            },
          ),
          IconButton(
            tooltip: 'Refresh Memories',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadMemories,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search memories, OCR texts, phone numbers...',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: primaryEmerald, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white60, size: 16),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: surfaceCard,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: primaryEmerald),
                ),
              ),
            ),
          ),

          // Category Filter Tabs
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _filterTabs.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tab = _filterTabs[index];
                final id = tab['id'] as String;
                final label = tab['label'] as String;
                final icon = tab['icon'] as IconData;
                final isSelected = _activeCategory == id;

                int count = 0;
                if (id == 'all') {
                  count = _allNodes.length;
                } else if (id == 'daily_summary') {
                  count = _dailySummaries.length;
                } else {
                  count = _allNodes.where((n) => n.category == id).length;
                }

                return ChoiceChip(
                  avatar: Icon(
                    icon,
                    size: 13,
                    color: isSelected ? Colors.black : Colors.white70,
                  ),
                  label: Text('$label ($count)'),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.black : Colors.white,
                  ),
                  selected: isSelected,
                  selectedColor: primaryEmerald,
                  backgroundColor: surfaceCard,
                  side: BorderSide(
                    color: isSelected ? primaryEmerald : borderColor,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _activeCategory = id;
                      });
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Main List View
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: primaryEmerald))
                : (_activeCategory == 'daily_summary' && filteredNodes.isEmpty)
                    ? _buildDailySummariesList()
                    : filteredNodes.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.only(left: 14, right: 14, top: 4, bottom: 20),
                            itemCount: filteredNodes.length,
                            itemBuilder: (context, index) {
                              return _buildMemoryCard(filteredNodes[index]);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryCard(DecryptedMemoryNode node) {
    Color categoryColor = primaryEmerald;
    IconData categoryIcon = Icons.memory;

    switch (node.category) {
      case MemoryCategory.ocrDoc:
        categoryColor = const Color(0xFFC084FC);
        categoryIcon = Icons.document_scanner;
        break;
      case MemoryCategory.screenTime:
        categoryColor = const Color(0xFF06B6D4);
        categoryIcon = Icons.timer;
        break;
      case MemoryCategory.callLog:
        categoryColor = const Color(0xFF8B5CF6);
        categoryIcon = Icons.call;
        break;
      case MemoryCategory.transaction:
        categoryColor = const Color(0xFF10B981);
        categoryIcon = Icons.account_balance_wallet;
        break;
      case 'app_usage':
        categoryColor = const Color(0xFF38BDF8);
        categoryIcon = Icons.apps;
        break;
      case MemoryCategory.note:
      case 'system_note':
        categoryColor = amberAlert;
        categoryIcon = Icons.note_outlined;
        break;
    }

    final dateStr = DateFormat('MMM d, yyyy • HH:mm').format(node.timestamp);

    // Extract metadata details if available
    String displayName = '';
    String? mimeType;
    if (node.metadataJson.isNotEmpty) {
      try {
        final map = jsonDecode(node.metadataJson) as Map<String, dynamic>;
        displayName = (map['displayName'] ?? map['fileName'] ?? '').toString();
        mimeType = map['mimeType']?.toString();
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Category Badge + Timestamp + Delete
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: categoryColor.withValues(alpha: 0.4), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(categoryIcon, size: 12, color: categoryColor),
                    const SizedBox(width: 4),
                    Text(
                      node.category.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: categoryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (node.isPinned)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: amberAlert.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '📌 PINNED',
                    style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: amberAlert),
                  ),
                ),
              const Spacer(),
              Text(
                dateStr,
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white38),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _handleDeleteNode(node),
              ),
            ],
          ),

          if (displayName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              displayName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Decrypted Content Container
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF090E17),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: SelectableText(
              node.content,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFE2E8F0),
                height: 1.42,
              ),
            ),
          ),

          // File Open Action (if external fileUri exists)
          if (node.fileUri != null && node.fileUri!.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _handleOpenFile(node.fileUri!, mimeType: mimeType),
                icon: const Icon(Icons.open_in_new, size: 13),
                label: Text(
                  'Open File (${node.fileUri!.split(RegExp(r'[/\\]')).last})',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: categoryColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDailySummariesList() {
    if (_dailySummaries.isEmpty) return _buildEmptyState();

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _dailySummaries.length,
      itemBuilder: (context, index) {
        final summary = _dailySummaries[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: surfaceCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: amberAlert.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_graph_rounded, color: amberAlert, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Daily Digest: ${summary.date}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: amberAlert.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${summary.totalScreenTimeMinutes}m • ₹${summary.totalSpent.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 9.5, color: amberAlert, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              if (summary.summaryText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  summary.summaryText,
                  style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.3),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, color: Colors.grey.shade600, size: 48),
            const SizedBox(height: 12),
            const Text(
              'No Encrypted Memories Found',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No records match "$_searchQuery" in this category.'
                  : 'Sync phone signals or upload a document to build your local vault.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}
