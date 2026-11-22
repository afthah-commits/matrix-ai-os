import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/models/document_classification.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/document_classifier.dart';

/// Result returned after picking and inspecting a document for upload.
class PickedDocumentData {
  final String uri;
  final String filePath;
  final String fileName;
  final String mimeType;
  final int fileSize;

  const PickedDocumentData({
    required this.uri,
    required this.filePath,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
  });

  bool get isPdf =>
      mimeType == 'application/pdf' || fileName.toLowerCase().endsWith('.pdf');
}

/// Result returned when a document is permanently encrypted and indexed into ObjectBox.
class ManualUploadResult {
  final int id;
  final String title;
  final String category;
  final String extractedText;
  final String fileUri;
  final String mimeType;
  final DateTime timestamp;

  const ManualUploadResult({
    required this.id,
    required this.title,
    required this.category,
    required this.extractedText,
    required this.fileUri,
    required this.mimeType,
    required this.timestamp,
  });
}

/// Service managing the manual Document & ID Card Vault uploader.
///
/// Features:
/// - Lightweight, zero-bloat file picking via Android native Intent
/// - Instant 100% on-device Google ML Kit OCR text extraction
/// - Automatic entity classification + custom tags/titles
/// - Permanent encrypted storage in ObjectBox (`isPinned: true`)
/// - Automatic Knowledge Graph edge linking
class ManualDocumentVaultService {
  final LocalDatabaseService _dbService;
  final ActionDispatcherService _actionDispatcher;
  TextRecognizer? _textRecognizer;

  ManualDocumentVaultService({
    required LocalDatabaseService dbService,
    required ActionDispatcherService actionDispatcher,
    TextRecognizer? textRecognizer,
  })  : _dbService = dbService,
        _actionDispatcher = actionDispatcher,
        _textRecognizer = textRecognizer;

  TextRecognizer _getRecognizer() {
    return _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
  }

  /// Prompts user to pick an image or PDF document using Android's native file picker.
  Future<PickedDocumentData?> pickDocument() async {
    final res = await _actionDispatcher.pickDocumentOrImage();
    if (res['success'] == true) {
      return PickedDocumentData(
        uri: (res['uri'] ?? '').toString(),
        filePath: (res['filePath'] ?? '').toString(),
        fileName: (res['fileName'] ?? 'document').toString(),
        mimeType: (res['mimeType'] ?? 'application/octet-stream').toString(),
        fileSize: (res['fileSize'] as num?)?.toInt() ?? 0,
      );
    }
    return null;
  }

  /// Performs instant on-device OCR on the picked document (Image or PDF page 0).
  Future<String> extractOcrText(PickedDocumentData data) async {
    try {
      if (data.isPdf) {
        // PDF: Render page 0 to temporary image using Android PdfRenderer
        final renderRes = await _actionDispatcher.renderPdfPageForOcr(data.uri, pageIndex: 0);
        if (renderRes['success'] == true) {
          final imagePath = (renderRes['imagePath'] ?? '').toString();
          if (imagePath.isNotEmpty) {
            final tempFile = File(imagePath);
            if (await tempFile.exists()) {
              final inputImage = InputImage.fromFilePath(imagePath);
              final recognized = await _getRecognizer().processImage(inputImage);
              try {
                await tempFile.delete();
              } catch (_) {}
              return recognized.text.trim();
            }
          }
        }
        return '';
      } else {
        // Image: Direct ML Kit text recognition
        if (data.filePath.isNotEmpty) {
          final file = File(data.filePath);
          if (await file.exists()) {
            final inputImage = InputImage.fromFilePath(data.filePath);
            final recognized = await _getRecognizer().processImage(inputImage);
            return recognized.text.trim();
          }
        }
        return '';
      }
    } catch (e) {
      debugPrint('[ManualDocumentVaultService] OCR extraction error: $e');
      return '';
    }
  }

  /// Categorizes extracted text.
  DocumentClassification classify(String text) {
    return DocumentClassifier.classify(text);
  }

  /// Encrypts and saves the document to the ObjectBox vault.
  Future<ManualUploadResult> saveToVault({
    required PickedDocumentData pickedData,
    required String customTitle,
    required String customCategory,
    required String extractedText,
  }) async {
    final finalTitle = customTitle.trim().isNotEmpty
        ? customTitle.trim()
        : pickedData.fileName;

    final classification = classify(extractedText);

    final metadata = jsonEncode({
      'displayName': finalTitle,
      'docCategory': customCategory,
      'classification': classification.toMap(),
      'charCount': extractedText.length,
      'fileName': pickedData.fileName,
      'mimeType': pickedData.mimeType,
      'fileSize': pickedData.fileSize,
      'manualUpload': true,
      'uploadedAt': DateTime.now().toIso8601String(),
    });

    final contentToStore = extractedText.isNotEmpty
        ? extractedText
        : 'Document: $finalTitle (${pickedData.fileName})';

    // 1. Encrypt and persist as a permanent MemoryNode (immune from rolling auto-pruning)
    final node = await _dbService.insertMemoryNode(
      category: MemoryCategory.ocrDoc,
      content: contentToStore,
      metadataJson: metadata,
      timestamp: DateTime.now(),
      fileUri: pickedData.uri.isNotEmpty ? pickedData.uri : pickedData.filePath,
      isPinned: true,
    );

    // 2. Reinforce Knowledge Graph relation
    try {
      final contextSnippet = extractedText.length > 120
          ? '${extractedText.substring(0, 120)}...'
          : extractedText;
      await _dbService.upsertEdge(
        sourceEntity: 'User',
        relationType: 'OWNS_DOCUMENT',
        targetEntity: finalTitle,
        context: contextSnippet,
      );
    } catch (e) {
      debugPrint('[ManualDocumentVaultService] KG link error: $e');
    }

    return ManualUploadResult(
      id: node.id,
      title: finalTitle,
      category: customCategory,
      extractedText: contentToStore,
      fileUri: node.fileUri ?? pickedData.uri,
      mimeType: pickedData.mimeType,
      timestamp: node.timestamp,
    );
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
