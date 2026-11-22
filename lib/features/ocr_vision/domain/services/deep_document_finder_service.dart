import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/models/document_classification.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/document_classifier.dart';

/// Structured match result returned when locating personal documents, passports, or receipts.
@immutable
class DocumentMatchResult {
  final int id;
  final String title;
  final String category; // 'PASSPORT_ID', 'TICKET_BOOKING', 'INVOICE_RECEIPT', 'BANK_STATEMENT', 'GENERAL_NOTE'
  final String extractedSummary;
  final Map<String, dynamic> keyFields;
  final String fileUri;
  final String mimeType;
  final DateTime timestamp;
  final bool fromLiveScan;

  const DocumentMatchResult({
    this.id = 0,
    required this.title,
    required this.category,
    required this.extractedSummary,
    this.keyFields = const {},
    required this.fileUri,
    this.mimeType = 'image/jpeg',
    required this.timestamp,
    this.fromLiveScan = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'category': category,
    'extractedSummary': extractedSummary,
    'keyFields': keyFields,
    'fileUri': fileUri,
    'mimeType': mimeType,
    'timestamp': timestamp.toIso8601String(),
    'fromLiveScan': fromLiveScan,
  };

  factory DocumentMatchResult.fromMap(Map<String, dynamic> map) {
    return DocumentMatchResult(
      id: (map['id'] as num?)?.toInt() ?? 0,
      title: map['title'] as String? ?? 'Document',
      category: map['category'] as String? ?? 'GENERAL_NOTE',
      extractedSummary: map['extractedSummary'] as String? ?? '',
      keyFields: Map<String, dynamic>.from(map['keyFields'] as Map? ?? {}),
      fileUri: map['fileUri'] as String? ?? '',
      mimeType: map['mimeType'] as String? ?? 'image/jpeg',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      fromLiveScan: map['fromLiveScan'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'DocumentMatchResult($title, $category, uri: $fileUri, live: $fromLiveScan)';
}

/// Deep Document, Passport & PDF Finder Service.
///
/// Executes a two-stage retrieval pipeline:
/// 1. Fast encrypted vault lookup in ObjectBox (`ocr_doc` category).
/// 2. Live on-demand device scan (MediaStore Images + PDFs) when vault misses or explicitly asked,
///    running lightweight Google ML Kit OCR (with native Android `PdfRenderer` for PDFs)
///    and automatically caching newly discovered documents encrypted with zero file duplication.
class DeepDocumentFinderService {
  final LocalDatabaseService _dbService;
  final MethodChannel _channel;
  TextRecognizer? _textRecognizer;

  DeepDocumentFinderService({
    required LocalDatabaseService dbService,
    MethodChannel? channel,
    TextRecognizer? textRecognizer,
  })  : _dbService = dbService,
        _channel = channel ?? const MethodChannel(ActionDispatcherService.channelName),
        _textRecognizer = textRecognizer;

  TextRecognizer _getRecognizer() {
    return _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
  }

  /// Finds documents matching [query] across ObjectBox vault and on-demand live storage.
  Future<List<DocumentMatchResult>> findDocument(
    String query, {
    bool forceLiveScan = false,
    int maxScanCandidates = 5,
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    // Stage 1: Fast Encrypted Vault Lookup in ObjectBox
    if (!forceLiveScan) {
      final vaultMatches = await searchEncryptedVault(cleanQuery);
      if (vaultMatches.isNotEmpty) {
        debugPrint('[DeepDocumentFinder] Found ${vaultMatches.length} matching document(s) in encrypted vault.');
        return vaultMatches;
      }
    }

    // Stage 2: Live On-Demand Device Scan (MediaStore Images + PDFs)
    debugPrint('[DeepDocumentFinder] Vault miss for "$query". Initiating live device scan...');
    final liveMatches = await scanDeviceStorageOnDemand(
      cleanQuery,
      maxScanCandidates: maxScanCandidates,
    );
    return liveMatches;
  }

  /// Searches encrypted `ocr_doc` nodes in ObjectBox matching [cleanQuery].
  Future<List<DocumentMatchResult>> searchEncryptedVault(String cleanQuery) async {
    try {
      final decryptedNodes = await _dbService.getDecryptedNodesByCategory(
        MemoryCategory.ocrDoc,
        limit: 100,
      );

      final matches = <DocumentMatchResult>[];

      for (final decrypted in decryptedNodes) {
        final content = decrypted.content;
        final metadataJson = decrypted.metadataJson;

        Map<String, dynamic> metadata = {};
        if (metadataJson.isNotEmpty) {
          try {
            metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
          } catch (_) {}
        }

        final classificationMap = metadata['classification'] as Map<String, dynamic>?;
        final classification = classificationMap != null
            ? DocumentClassification.fromMap(classificationMap)
            : DocumentClassifier.classify(content);

        final displayName = metadata['displayName']?.toString() ??
            metadata['assetId']?.toString() ??
            '';

        if (_isDocumentRelevant(cleanQuery, content, classification, displayName)) {
          matches.add(DocumentMatchResult(
            id: decrypted.id,
            title: displayName.isNotEmpty ? displayName : _generateTitle(classification),
            category: classification.type.displayName,
            extractedSummary: classification.summary.isNotEmpty ? classification.summary : content,
            keyFields: classification.entities.toMap(),
            fileUri: decrypted.fileUri ?? '',
            mimeType: metadata['mimeType']?.toString() ??
                (decrypted.fileUri?.endsWith('.pdf') == true ? 'application/pdf' : 'image/jpeg'),
            timestamp: decrypted.timestamp,
            fromLiveScan: false,
          ));
        }
      }

      return matches;
    } catch (e) {
      debugPrint('[DeepDocumentFinder] Error during vault search: $e');
      return [];
    }
  }

  /// Queries Android MediaStore for relevant images & PDFs and performs on-demand OCR.
  Future<List<DocumentMatchResult>> scanDeviceStorageOnDemand(
    String cleanQuery, {
    int maxScanCandidates = 5,
  }) async {
    final liveMatches = <DocumentMatchResult>[];

    try {
      // 1. Search device files via native MediaStore query
      final rawList = await _channel.invokeListMethod<dynamic>(
        'searchDeviceFiles',
        {'query': cleanQuery},
      );

      if (rawList == null || rawList.isEmpty) {
        debugPrint('[DeepDocumentFinder] No candidate files returned from device storage.');
        return [];
      }

      // 2. Query already-indexed file URIs to prevent redundant OCR
      final existingNodes = await _dbService.getDecryptedNodesByCategory(
        MemoryCategory.ocrDoc,
        limit: 500,
      );
      final existingUris = existingNodes
          .map((m) => m.fileUri)
          .whereType<String>()
          .toSet();

      int scannedCount = 0;

      for (final raw in rawList) {
        if (scannedCount >= maxScanCandidates) break;

        final item = Map<String, dynamic>.from(raw as Map);
        final uri = (item['uri'] ?? '').toString();
        final displayName = (item['displayName'] ?? '').toString();
        final mimeType = (item['mimeType'] ?? '').toString();
        final filePath = (item['filePath'] ?? '').toString();

        final effectiveUri = uri.isNotEmpty ? uri : filePath;
        if (existingUris.contains(effectiveUri) || (filePath.isNotEmpty && existingUris.contains(filePath))) {
          continue;
        }

        String extractedText = '';

        // 3. Extract text: Handle PDF via native PdfRenderer or Image via direct ML Kit
        if (mimeType == 'application/pdf' || displayName.toLowerCase().endsWith('.pdf')) {
          final renderRes = await _channel.invokeMapMethod<String, dynamic>(
            'renderPdfPageForOcr',
            {'contentUri': uri.isNotEmpty ? uri : filePath, 'pageIndex': 0},
          );

          if (renderRes != null && renderRes['success'] == true) {
            final imagePath = (renderRes['imagePath'] ?? '').toString();
            if (imagePath.isNotEmpty) {
              final tempFile = File(imagePath);
              if (await tempFile.exists()) {
                final inputImage = InputImage.fromFilePath(imagePath);
                final recognized = await _getRecognizer().processImage(inputImage);
                extractedText = recognized.text.trim();
                // Clean up temporary rendered JPEG page
                try {
                  await tempFile.delete();
                } catch (_) {}
              }
            }
          }
        } else {
          // Image OCR via direct file path
          if (filePath.isNotEmpty) {
            final imgFile = File(filePath);
            if (await imgFile.exists()) {
              final inputImage = InputImage.fromFilePath(filePath);
              final recognized = await _getRecognizer().processImage(inputImage);
              extractedText = recognized.text.trim();
            }
          }
        }

        scannedCount++;

        // 4. If extracted content is meaningful, classify and persist
        if (extractedText.length >= 15) {
          final classification = DocumentClassifier.classify(extractedText);

          if (_isDocumentRelevant(cleanQuery, extractedText, classification, displayName)) {
            final metadata = jsonEncode({
              'classification': classification.toMap(),
              'charCount': extractedText.length,
              'displayName': displayName,
              'mimeType': mimeType,
              'source': 'on_demand_live_scan',
            });

            // Persist as a permanent pinned MemoryNode in ObjectBox (zero image duplication)
            final node = await _dbService.insertMemoryNode(
              category: MemoryCategory.ocrDoc,
              content: extractedText,
              metadataJson: metadata,
              timestamp: DateTime.now(),
              fileUri: effectiveUri,
              isPinned: true,
            );

            existingUris.add(effectiveUri);

            liveMatches.add(DocumentMatchResult(
              id: node.id,
              title: displayName.isNotEmpty ? displayName : _generateTitle(classification),
              category: classification.type.displayName,
              extractedSummary: classification.summary,
              keyFields: classification.entities.toMap(),
              fileUri: effectiveUri,
              mimeType: mimeType,
              timestamp: node.timestamp,
              fromLiveScan: true,
            ));

            debugPrint('[DeepDocumentFinder] Live-indexed candidate: $displayName (${classification.type.displayName})');
          }
        }
      }
    } catch (e) {
      debugPrint('[DeepDocumentFinder] Error during live device scan: $e');
    }

    return liveMatches;
  }

  /// Determines whether a document matches the user's intent query.
  bool _isDocumentRelevant(
    String query,
    String text,
    DocumentClassification classification,
    String displayName,
  ) {
    final q = query.toLowerCase();
    final t = text.toLowerCase();
    final name = displayName.toLowerCase();

    if (q.contains('passport')) {
      return classification.type == DocumentType.passportId ||
          t.contains('passport') ||
          t.contains('republic of india') ||
          name.contains('passport');
    }

    if (q.contains('password') || q.contains('passcode') || q.contains('secret') || q.contains('credential')) {
      return t.contains('password') ||
          t.contains('passcode') ||
          t.contains('secret') ||
          t.contains('credential') ||
          name.contains('password');
    }

    if (q.contains('ticket') || q.contains('boarding') || q.contains('flight') || q.contains('booking')) {
      return classification.type == DocumentType.ticketBooking ||
          t.contains('ticket') ||
          t.contains('boarding pass') ||
          t.contains('flight') ||
          t.contains('pnr') ||
          name.contains('ticket');
    }

    if (q.contains('invoice') || q.contains('bill') || q.contains('receipt')) {
      return classification.type == DocumentType.invoiceReceipt ||
          t.contains('invoice') ||
          t.contains('tax invoice') ||
          t.contains('receipt') ||
          t.contains('bill') ||
          name.contains('invoice') ||
          name.contains('receipt') ||
          name.contains('bill');
    }

    if (q.contains('statement')) {
      return classification.type == DocumentType.bankStatement ||
          t.contains('statement') ||
          name.contains('statement');
    }

    if (q.contains('pan') || q.contains('aadhaar') || q.contains('id card') || q.contains('license') || q.contains('licence')) {
      return classification.type == DocumentType.passportId ||
          t.contains('pan') ||
          t.contains('income tax') ||
          t.contains('aadhaar') ||
          name.contains('pan') ||
          name.contains('aadhaar') ||
          name.contains('id');
    }

    if (q.contains('പാസ്പോർട്ട്')) {
      return classification.type == DocumentType.passportId ||
          t.contains('passport') ||
          name.contains('passport') ||
          name.contains('പാസ്പോർട്ട്');
    }
    if (q.contains('ടിക്കറ്റ്')) {
      return classification.type == DocumentType.ticketBooking ||
          t.contains('ticket') ||
          name.contains('ticket') ||
          name.contains('ടിക്കറ്റ്');
    }
    if (q.contains('രേഖ') || q.contains('ഡോക്യുമെന്റ്') || q.contains('ഫയൽ')) {
      return true;
    }

    // Broad document queries
    if (q.contains('document') || q.contains('doc') || q.contains('pdf') || q.contains('find') || q.contains('search')) {
      return true;
    }

    return t.contains(q) || name.contains(q);
  }

  String _generateTitle(DocumentClassification classification) {
    switch (classification.type) {
      case DocumentType.passportId:
        final id = classification.entities.idNumber;
        return id != null ? 'Passport ($id)' : 'Passport Document';
      case DocumentType.ticketBooking:
        final issuer = classification.entities.merchantOrIssuer;
        return issuer != null ? '$issuer Ticket / Pass' : 'Boarding Pass / Ticket';
      case DocumentType.invoiceReceipt:
        final merchant = classification.entities.merchantOrIssuer;
        return merchant != null ? '$merchant Receipt' : 'Invoice / Receipt';
      case DocumentType.bankStatement:
        return 'Bank Statement';
      case DocumentType.generalNote:
        return 'Document Note';
    }
  }

  /// Releases ML Kit text recognizer resources.
  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
