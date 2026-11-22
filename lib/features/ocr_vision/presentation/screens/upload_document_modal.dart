import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/presentation/widgets/matrix_logo_widget.dart';
import 'package:matrix_ai_os/core/utils/formatters.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/controllers/dashboard_controller.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/manual_document_vault_service.dart';
import 'package:matrix_ai_os/features/ocr_vision/presentation/providers/ocr_vision_providers.dart';

/// Modal bottom sheet allowing users to manually pick an image or PDF from device,
/// extract OCR text locally on-device, assign a label/category, and save encrypted.
class UploadDocumentModal extends ConsumerStatefulWidget {
  const UploadDocumentModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const UploadDocumentModal(),
    );
  }

  @override
  ConsumerState<UploadDocumentModal> createState() => _UploadDocumentModalState();
}

class _UploadDocumentModalState extends ConsumerState<UploadDocumentModal> {
  final TextEditingController _titleController = TextEditingController();
  PickedDocumentData? _pickedData;
  String _extractedText = '';
  String _selectedCategory = 'PASSPORT_ID';
  bool _isOcrProcessing = false;
  bool _isSaving = false;
  String? _errorMessage;

  static const _categoryOptions = [
    {'code': 'PASSPORT_ID', 'label': 'Passport / ID', 'icon': Icons.badge},
    {'code': 'PAN_CARD', 'label': 'PAN Card', 'icon': Icons.credit_card},
    {'code': 'AADHAAR_CARD', 'label': 'Aadhaar Card', 'icon': Icons.perm_identity},
    {'code': 'TICKET_BOOKING', 'label': 'Ticket / Boarding Pass', 'icon': Icons.confirmation_number},
    {'code': 'INVOICE_RECEIPT', 'label': 'Invoice / Receipt', 'icon': Icons.receipt_long},
    {'code': 'BANK_STATEMENT', 'label': 'Bank Statement', 'icon': Icons.account_balance},
    {'code': 'GENERAL_NOTE', 'label': 'Other Document', 'icon': Icons.description},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _handlePickDocument() async {
    setState(() {
      _errorMessage = null;
    });

    final vaultService = ref.read(manualDocumentVaultServiceProvider);
    final data = await vaultService.pickDocument();
    if (data == null) return;

    setState(() {
      _pickedData = data;
      _isOcrProcessing = true;
      if (_titleController.text.trim().isEmpty) {
        _titleController.text = data.fileName.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      }
    });

    // Run on-device OCR
    final text = await vaultService.extractOcrText(data);

    // Auto-detect document category from extracted text
    final classification = vaultService.classify(text);
    String detectedCategory = 'GENERAL_NOTE';
    final lowerText = text.toLowerCase();
    final lowerName = data.fileName.toLowerCase();

    if (lowerText.contains('passport') || lowerName.contains('passport')) {
      detectedCategory = 'PASSPORT_ID';
    } else if (lowerText.contains('income tax') || lowerText.contains('permanent account number') || lowerName.contains('pan')) {
      detectedCategory = 'PAN_CARD';
    } else if (lowerText.contains('aadhaar') || lowerText.contains('unique identification') || lowerName.contains('aadhaar')) {
      detectedCategory = 'AADHAAR_CARD';
    } else if (lowerText.contains('ticket') || lowerText.contains('boarding') || lowerText.contains('pnr') || lowerName.contains('ticket')) {
      detectedCategory = 'TICKET_BOOKING';
    } else if (lowerText.contains('invoice') || lowerText.contains('tax invoice') || lowerText.contains('receipt') || lowerName.contains('receipt')) {
      detectedCategory = 'INVOICE_RECEIPT';
    } else if (lowerText.contains('statement') || lowerName.contains('statement')) {
      detectedCategory = 'BANK_STATEMENT';
    } else {
      detectedCategory = classification.type.name;
    }

    if (mounted) {
      setState(() {
        _extractedText = text;
        _isOcrProcessing = false;
        _selectedCategory = detectedCategory;
      });
    }
  }

  Future<void> _handleSave() async {
    if (_pickedData == null) {
      setState(() {
        _errorMessage = 'Please choose a document or image first';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final vaultService = ref.read(manualDocumentVaultServiceProvider);
      final result = await vaultService.saveToVault(
        pickedData: _pickedData!,
        customTitle: _titleController.text,
        customCategory: _selectedCategory,
        extractedText: _extractedText,
      );

      // Refresh dashboard stats
      await ref.read(dashboardControllerProvider.notifier).refreshMetrics();

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF065F46),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Encrypted & Saved "${result.title}" to Vault!',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to save document: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryEmerald = Color(0xFF10B981);
    const neonCyan = Color(0xFF06B6D4);
    const bgContainer = Color(0xFF0F172A);
    const surfaceCard = Color(0xFF161B22);
    const borderColor = Color(0xFF30363D);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: bgContainer,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: borderColor, width: 1.5)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
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

            // Modal Header
            Row(
              children: [
                const MatrixLogoWidget(size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Upload Document / ID Card',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '100% On-Device ML Kit OCR • Encrypted Vault',
                        style: TextStyle(
                          fontSize: 11,
                          color: neonCyan,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F1D1D).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // File Pick Zone
            if (_pickedData == null)
              GestureDetector(
                onTap: _handlePickDocument,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: surfaceCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: primaryEmerald.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryEmerald.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.cloud_upload_outlined,
                          color: primaryEmerald,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Choose Image or PDF Document',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Supports Passports, PAN Cards, IDs, Tickets & Receipts',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        children: [
                          _buildMiniBadge('Images (JPG, PNG)', neonCyan),
                          _buildMiniBadge('PDF Documents', primaryEmerald),
                          _buildMiniBadge('Zero Cloud Leakage', const Color(0xFFC084FC)),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryEmerald.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _pickedData!.isPdf ? Icons.picture_as_pdf : Icons.image,
                      color: _pickedData!.isPdf ? Colors.redAccent : primaryEmerald,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _pickedData!.fileName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${Formatters.formatBytes(_pickedData!.fileSize)} • ${_pickedData!.mimeType}',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _handlePickDocument,
                      icon: const Icon(Icons.change_circle_outlined, size: 14),
                      label: const Text('Change', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(foregroundColor: neonCyan),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Title / Label Input
            const Text(
              'Document Title / Custom Label',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 13, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. My Passport, PAN Card, Flight Ticket...',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                filled: true,
                fillColor: surfaceCard,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              ),
            ),

            const SizedBox(height: 14),

            // Document Category Tag Selector
            const Text(
              'Document Tag / Category',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _categoryOptions.map((opt) {
                final code = opt['code'] as String;
                final label = opt['label'] as String;
                final icon = opt['icon'] as IconData;
                final isSelected = _selectedCategory == code;

                return ChoiceChip(
                  avatar: Icon(
                    icon,
                    size: 13,
                    color: isSelected ? Colors.black : Colors.white70,
                  ),
                  label: Text(label),
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedCategory = code;
                      });
                    }
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 14),

            // Extracted OCR Preview
            if (_isOcrProcessing)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: primaryEmerald),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Running on-device Google ML Kit OCR...',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              )
            else if (_extractedText.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Extracted OCR Content (Encrypted in Vault)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                      Text(
                        '${_extractedText.length} chars',
                        style: const TextStyle(fontSize: 10, color: neonCyan),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 110),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090E17),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _extractedText,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          color: Color(0xFFE2E8F0),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 20),

            // Action Buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_pickedData == null || _isSaving || _isOcrProcessing)
                    ? null
                    : _handleSave,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.lock_rounded, size: 16),
                label: Text(
                  _isSaving ? 'Encrypting & Saving to Vault...' : 'Save to Encrypted Vault',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryEmerald,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
