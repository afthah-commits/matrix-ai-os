import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/core/database/models/memory_node.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/document_classifier.dart';
import 'package:matrix_ai_os/objectbox.g.dart';

/// On-Device Gallery OCR & Visual Document Indexing Service.
///
/// Features:
/// - 100% on-device offline OCR via Google ML Kit Text Recognition
/// - Zero Image Duplication (only stores external fileUri and extracted metadata)
/// - Incremental scanning (avoids re-processing previously scanned assets)
/// - Filtering: Ignores noise/selfie images (<15 chars) to prevent storage waste
/// - Immunity: All indexed documents are saved with isPinned: true (exempt from rolling pruning)
class GalleryOcrService {
  final LocalDatabaseService _dbService;
  TextRecognizer? _textRecognizer;

  GalleryOcrService({required LocalDatabaseService dbService})
      : _dbService = dbService;

  TextRecognizer _getRecognizer() {
    return _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
  }

  /// Checks if photo/gallery permission is granted.
  Future<bool> hasGalleryPermission() async {
    try {
      final state = await PhotoManager.requestPermissionExtend();
      return state.hasAccess;
    } catch (e) {
      debugPrint('[GalleryOcrService] Permission check error: $e');
      return false;
    }
  }

  /// Incrementally scans recent gallery images, extracts OCR text, classifies documents,
  /// and persists encrypted MemoryNodes.
  Future<List<MemoryNode>> scanAndIndexRecentImages({
    int maxScanCount = 20,
    TextRecognizer? customRecognizer,
  }) async {
    final hasPerm = await hasGalleryPermission();
    if (!hasPerm) {
      debugPrint('[GalleryOcrService] Gallery access permission not granted.');
      return [];
    }

    final recognizer = customRecognizer ?? _getRecognizer();
    final indexedNodes = <MemoryNode>[];

    try {
      // 1. Fetch recent albums
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );

      if (albums.isEmpty) return [];

      final recentAlbum = albums.first;
      final assets = await recentAlbum.getAssetListPaged(
        page: 0,
        size: maxScanCount,
      );

      final memoryBox = _dbService.memoryBox;

      // 2. Query already-indexed file URIs to prevent re-processing
      final existingOcrQuery = (memoryBox.query(
        MemoryNode_.category.equals(MemoryCategory.ocrDoc),
      )).build();

      final existingUris = existingOcrQuery
          .find()
          .map((n) => n.fileUri)
          .whereType<String>()
          .toSet();
      existingOcrQuery.close();

      debugPrint('[GalleryOcrService] Scanning ${assets.length} recent assets. Existing OCR docs: ${existingUris.length}');

      for (final asset in assets) {
        final File? file = await asset.file;
        if (file == null || !await file.exists()) continue;

        // Skip if already indexed
        if (existingUris.contains(file.path)) {
          continue;
        }

        // 3. Run On-Device ML Kit Text Recognition
        final inputImage = InputImage.fromFilePath(file.path);
        final RecognizedText recognized = await recognizer.processImage(inputImage);
        final extractedText = recognized.text.trim();

        // 4. Noise filtering: ignore non-document pictures (selfies, landscapes, memes)
        if (extractedText.length < 15) {
          existingUris.add(file.path);
          continue;
        }

        // 5. Categorize and extract entities
        final classification = DocumentClassifier.classify(extractedText);

        final metadata = jsonEncode({
          'classification': classification.toMap(),
          'charCount': extractedText.length,
          'assetId': asset.id,
          'mimeType': asset.mimeType ?? 'image/jpeg',
          'createDateTime': asset.createDateTime.toIso8601String(),
        });

        // 6. Encrypt and persist as a permanent MemoryNode
        final node = await _dbService.insertMemoryNode(
          category: MemoryCategory.ocrDoc,
          content: extractedText,
          metadataJson: metadata,
          timestamp: asset.createDateTime,
          fileUri: file.path, // ZERO image duplication: reference path only
          isPinned: true, // Permanent knowledge: immune from rolling 30-day auto-pruner
        );

        existingUris.add(file.path);
        indexedNodes.add(node);

        debugPrint('[GalleryOcrService] Indexed OCR Document #${node.id} (${classification.type.displayName}) from ${file.path}');
      }
    } catch (e, stack) {
      debugPrint('[GalleryOcrService] Error during gallery OCR indexing: $e\n$stack');
    }

    return indexedNodes;
  }

  /// Closes ML Kit native recognizer resources.
  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
