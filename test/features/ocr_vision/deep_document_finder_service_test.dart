import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/core/database/models/memory_node.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/deep_document_finder_service.dart';

class FakeTextRecognizer extends Fake implements TextRecognizer {
  final String textToReturn;
  FakeTextRecognizer([this.textToReturn = 'REPUBLIC OF INDIA PASSPORT A1234567 DOE JOHN']);

  @override
  Future<RecognizedText> processImage(InputImage inputImage) async {
    return RecognizedText(
      text: textToReturn,
      blocks: const [],
    );
  }

  @override
  Future<void> close() async {}
}

class FakeLocalDatabaseServiceForFinder extends Fake implements LocalDatabaseService {
  final List<DecryptedMemoryNode> vaultNodes;
  final List<Map<String, dynamic>> insertedNodes = [];

  FakeLocalDatabaseServiceForFinder({this.vaultNodes = const []});

  @override
  Future<List<DecryptedMemoryNode>> getDecryptedNodesByCategory(
    String category, {
    int limit = 50,
  }) async {
    if (category == MemoryCategory.ocrDoc) {
      return vaultNodes;
    }
    return [];
  }

  @override
  Future<MemoryNode> insertMemoryNode({
    required String category,
    required String content,
    String metadataJson = '',
    DateTime? timestamp,
    String? fileUri,
    bool isPinned = false,
  }) async {
    insertedNodes.add({
      'category': category,
      'content': content,
      'metadataJson': metadataJson,
      'fileUri': fileUri,
      'isPinned': isPinned,
    });
    return MemoryNode(
      id: insertedNodes.length,
      category: category,
      content: content,
      metadataJson: metadataJson,
      timestamp: timestamp ?? DateTime.now(),
      fileUri: fileUri,
      isPinned: isPinned,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLocalDatabaseServiceForFinder fakeDb;
  late DeepDocumentFinderService finderService;
  late FakeTextRecognizer fakeRecognizer;
  final List<MethodCall> channelCalls = [];
  late File tempPdfImage;

  setUp(() async {
    channelCalls.clear();
    final tempDir = Directory.systemTemp.createTempSync('matrix_finder_test');
    tempPdfImage = File('${tempDir.path}/temp_page_0.jpg')..writeAsStringSync('dummy image content');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(ActionDispatcherService.channelName),
      (MethodCall call) async {
        channelCalls.add(call);
        switch (call.method) {
          case 'searchDeviceFiles':
            return [
              {
                'uri': 'content://media/external/files/1001',
                'displayName': 'Air_India_Flight_Ticket.pdf',
                'mimeType': 'application/pdf',
                'dateModified': 1700000000000,
                'sizeBytes': 123456,
                'filePath': '/storage/emulated/0/Download/Air_India_Flight_Ticket.pdf',
              },
              {
                'uri': 'content://media/external/images/2002',
                'displayName': 'IMG_Passport_Scan.jpg',
                'mimeType': 'image/jpeg',
                'dateModified': 1700000000000,
                'sizeBytes': 654321,
                'filePath': tempPdfImage.path,
              },
            ];

          case 'renderPdfPageForOcr':
            return {
              'success': true,
              'imagePath': tempPdfImage.path,
              'pageCount': 1,
              'pageIndex': 0,
            };

          case 'openFileUri':
            return {
              'success': true,
              'message': 'Opened file',
            };

          default:
            return null;
        }
      },
    );

    fakeRecognizer = FakeTextRecognizer('REPUBLIC OF INDIA PASSPORT A1234567 DOE JOHN');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(ActionDispatcherService.channelName),
      null,
    );
    try {
      tempPdfImage.parent.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('DeepDocumentFinderService Stage 1: Encrypted Vault Retrieval', () {
    test('Finds matching passport in encrypted ObjectBox vault without live scan', () async {
      final passportNode = DecryptedMemoryNode(
        id: 42,
        category: MemoryCategory.ocrDoc,
        content: 'REPUBLIC OF INDIA PASSPORT Z9876543 SMITH JANE',
        metadataJson: '{"displayName": "Jane_Passport.jpg", "classification": {"type": "PASSPORT_ID", "summary": "Indian Passport for Jane Smith", "entities": {"idNumber": "Z9876543"}}}',
        timestamp: DateTime.now(),
        fileUri: 'content://media/external/images/42',
        isPinned: true,
      );

      fakeDb = FakeLocalDatabaseServiceForFinder(vaultNodes: [passportNode]);
      finderService = DeepDocumentFinderService(
        dbService: fakeDb,
        textRecognizer: fakeRecognizer,
      );

      final results = await finderService.findDocument('Find my passport');

      expect(results.length, equals(1));
      final doc = results.first;
      expect(doc.id, equals(42));
      expect(doc.title, equals('Jane_Passport.jpg'));
      expect(doc.category, equals('PASSPORT_ID'));
      expect(doc.keyFields['idNumber'], equals('Z9876543'));
      expect(doc.fileUri, equals('content://media/external/images/42'));
      expect(doc.fromLiveScan, isFalse);

      // Verify native MediaStore search was NOT called since vault had an exact match
      expect(channelCalls.where((c) => c.method == 'searchDeviceFiles'), isEmpty);
    });

    test('Finds matching flight ticket in encrypted vault', () async {
      final ticketNode = DecryptedMemoryNode(
        id: 88,
        category: MemoryCategory.ocrDoc,
        content: 'AIR INDIA BOARDING PASS PNR ABC123 FLIGHT AI101 DELHI TO LONDON',
        metadataJson: '{"displayName": "Boarding_Pass.pdf", "classification": {"type": "TICKET_BOOKING", "summary": "Air India Flight AI101 PNR ABC123", "entities": {"merchantOrIssuer": "Air India"}}}',
        timestamp: DateTime.now(),
        fileUri: 'content://media/external/files/88',
        isPinned: true,
      );

      fakeDb = FakeLocalDatabaseServiceForFinder(vaultNodes: [ticketNode]);
      finderService = DeepDocumentFinderService(
        dbService: fakeDb,
        textRecognizer: fakeRecognizer,
      );

      final results = await finderService.findDocument('Show my ticket');

      expect(results.length, equals(1));
      expect(results.first.category, equals('TICKET_BOOKING'));
      expect(results.first.title, equals('Boarding_Pass.pdf'));
      expect(results.first.fromLiveScan, isFalse);
    });
  });

  group('DeepDocumentFinderService Stage 2: Live On-Demand Device Scan & OCR', () {
    test('Falls back to live device scan and runs OCR when vault misses', () async {
      fakeDb = FakeLocalDatabaseServiceForFinder(vaultNodes: []); // Empty vault
      fakeRecognizer = FakeTextRecognizer('REPUBLIC OF INDIA PASSPORT M5544332 PATEL RAJ');

      finderService = DeepDocumentFinderService(
        dbService: fakeDb,
        textRecognizer: fakeRecognizer,
      );

      final results = await finderService.findDocument('Find my passport');

      expect(results.isNotEmpty, isTrue);
      final doc = results.firstWhere((d) => d.category == 'PASSPORT_ID');
      expect(doc.fromLiveScan, isTrue);
      expect(doc.keyFields['idNumber'], equals('M5544332'));

      // Verify native MediaStore search was executed
      expect(channelCalls.any((c) => c.method == 'searchDeviceFiles'), isTrue);

      // Verify discovered document was persisted encrypted into ObjectBox
      expect(fakeDb.insertedNodes.length, greaterThanOrEqualTo(1));
      final inserted = fakeDb.insertedNodes.first;
      expect(inserted['category'], equals(MemoryCategory.ocrDoc));
      expect(inserted['isPinned'], isTrue); // Permanent knowledge immunity
    });

    test('Renders PDF page 0 via native PdfRenderer and performs OCR', () async {
      fakeDb = FakeLocalDatabaseServiceForFinder(vaultNodes: []);
      fakeRecognizer = FakeTextRecognizer('AIR INDIA BOARDING PASS FLIGHT AI202 PNR XYZ789 BANGALORE TO SINGAPORE');

      finderService = DeepDocumentFinderService(
        dbService: fakeDb,
        textRecognizer: fakeRecognizer,
      );

      final results = await finderService.findDocument('Show my flight ticket');

      expect(results.isNotEmpty, isTrue);
      // Verify renderPdfPageForOcr was called for the PDF candidate
      expect(channelCalls.any((c) => c.method == 'renderPdfPageForOcr'), isTrue);
      expect(fakeDb.insertedNodes.any((n) => n['fileUri'] == 'content://media/external/files/1001'), isTrue);
      expect(fakeDb.insertedNodes.any((n) => n['metadataJson'].toString().contains('.pdf')), isTrue);
    });

    test('Skips already indexed files during on-demand scan', () async {
      // Vault already has the PDF indexed
      final existingNode = DecryptedMemoryNode(
        id: 1,
        category: MemoryCategory.ocrDoc,
        content: 'SOME INVOICE CONTENT',
        metadataJson: '{}',
        timestamp: DateTime.now(),
        fileUri: 'content://media/external/files/1001',
        isPinned: true,
      );

      fakeDb = FakeLocalDatabaseServiceForFinder(vaultNodes: [existingNode]);
      fakeRecognizer = FakeTextRecognizer('TAX INVOICE TOTAL 5000 USD');

      finderService = DeepDocumentFinderService(
        dbService: fakeDb,
        textRecognizer: fakeRecognizer,
      );

      // Force live scan
      await finderService.findDocument('find invoice', forceLiveScan: true);

      // Should not re-insert the already existing URI
      expect(
        fakeDb.insertedNodes.where((n) => n['fileUri'] == 'content://media/external/files/1001'),
        isEmpty,
      );
    });
  });
}
