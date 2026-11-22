import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/core/database/models/knowledge_edge.dart';
import 'package:matrix_ai_os/core/database/models/memory_node.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/deep_document_finder_service.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/manual_document_vault_service.dart';

class FakeLocalDatabaseServiceForVault extends Fake implements LocalDatabaseService {
  final List<DecryptedMemoryNode> nodes = [];
  final List<Map<String, dynamic>> edges = [];

  @override
  Future<MemoryNode> insertMemoryNode({
    required String category,
    required String content,
    String metadataJson = '',
    DateTime? timestamp,
    String? fileUri,
    bool isPinned = false,
  }) async {
    final id = nodes.length + 1;
    final time = timestamp ?? DateTime.now();
    nodes.add(DecryptedMemoryNode(
      id: id,
      category: category,
      content: content,
      metadataJson: metadataJson,
      timestamp: time,
      fileUri: fileUri,
      isPinned: isPinned,
    ));
    return MemoryNode(
      id: id,
      category: category,
      content: content,
      metadataJson: metadataJson,
      timestamp: time,
      fileUri: fileUri,
      isPinned: isPinned,
    );
  }

  @override
  Future<KnowledgeEdge> upsertEdge({
    required String sourceEntity,
    required String relationType,
    required String targetEntity,
    double weightDelta = 1.0,
    String context = '',
  }) async {
    edges.add({
      'source': sourceEntity,
      'relation': relationType,
      'target': targetEntity,
      'context': context,
      'weight': weightDelta,
    });
    return KnowledgeEdge(
      sourceEntity: sourceEntity,
      relationType: relationType,
      targetEntity: targetEntity,
      encryptedContext: context,
      weight: weightDelta,
      lastUpdated: DateTime.now(),
    );
  }

  @override
  Future<List<DecryptedMemoryNode>> getDecryptedNodesByCategory(
    String category, {
    int limit = 50,
  }) async {
    return nodes.where((n) => n.category == category).take(limit).toList();
  }

  @override
  Future<List<DecryptedMemoryNode>> getAllDecryptedNodes({int limit = 100}) async {
    return nodes.take(limit).toList();
  }

  @override
  Future<bool> deleteMemoryNode(int id) async {
    final idx = nodes.indexWhere((n) => n.id == id);
    if (idx != -1) {
      nodes.removeAt(idx);
      return true;
    }
    return false;
  }
}

class FakeActionDispatcherForVault extends Fake implements ActionDispatcherService {
  Map<String, dynamic> pickResult = {
    'success': true,
    'uri': 'content://media/external/images/media/42',
    'filePath': '/storage/emulated/0/Download/pan_card.jpg',
    'fileName': 'pan_card.jpg',
    'mimeType': 'image/jpeg',
    'fileSize': 102400,
  };

  @override
  Future<Map<String, dynamic>> pickDocumentOrImage() async {
    return pickResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLocalDatabaseServiceForVault fakeDb;
  late FakeActionDispatcherForVault fakeDispatcher;
  late ManualDocumentVaultService vaultService;

  setUp(() {
    fakeDb = FakeLocalDatabaseServiceForVault();
    fakeDispatcher = FakeActionDispatcherForVault();
    vaultService = ManualDocumentVaultService(
      dbService: fakeDb,
      actionDispatcher: fakeDispatcher,
    );
  });

  group('ManualDocumentVaultService Tests', () {
    test('pickDocument parses native picker result correctly', () async {
      final doc = await vaultService.pickDocument();

      expect(doc, isNotNull);
      expect(doc!.fileName, equals('pan_card.jpg'));
      expect(doc.filePath, equals('/storage/emulated/0/Download/pan_card.jpg'));
      expect(doc.mimeType, equals('image/jpeg'));
      expect(doc.isPdf, isFalse);
    });

    test('saveToVault stores pinned node with metadata and creates KG edge', () async {
      const picked = PickedDocumentData(
        uri: 'content://docs/my_passport.pdf',
        filePath: '/cache/vault_uploads/my_passport.pdf',
        fileName: 'my_passport.pdf',
        mimeType: 'application/pdf',
        fileSize: 204800,
      );

      final result = await vaultService.saveToVault(
        pickedData: picked,
        customTitle: 'Official Passport 2026',
        customCategory: 'passport',
        extractedText: 'REPUBLIC OF INDIA PASSPORT Z9482014 DOE JOHN DOB 15/08/1995',
      );

      expect(result.id, equals(1));
      expect(result.title, equals('Official Passport 2026'));
      expect(result.category, equals('passport'));

      // Verify node in DB
      expect(fakeDb.nodes.length, equals(1));
      final savedNode = fakeDb.nodes.first;
      expect(savedNode.category, equals(MemoryCategory.ocrDoc));
      expect(savedNode.isPinned, isTrue); // Permanent, immune from pruning
      expect(savedNode.fileUri, equals('content://docs/my_passport.pdf'));

      final meta = jsonDecode(savedNode.metadataJson) as Map<String, dynamic>;
      expect(meta['displayName'], equals('Official Passport 2026'));
      expect(meta['docCategory'], equals('passport'));
      expect(meta['manualUpload'], isTrue);

      // Verify Knowledge Graph edge
      expect(fakeDb.edges.length, equals(1));
      expect(fakeDb.edges.first['relation'], equals('OWNS_DOCUMENT'));
      expect(fakeDb.edges.first['target'], equals('Official Passport 2026'));
    });

    test('DeepDocumentFinderService finds manually uploaded vault documents', () async {
      // 1. Upload PAN card to vault
      const pickedPan = PickedDocumentData(
        uri: 'content://docs/pan_card.jpg',
        filePath: '/cache/vault_uploads/pan_card.jpg',
        fileName: 'pan_card.jpg',
        mimeType: 'image/jpeg',
        fileSize: 150000,
      );

      await vaultService.saveToVault(
        pickedData: pickedPan,
        customTitle: 'My Personal PAN Card',
        customCategory: 'id_card',
        extractedText: 'INCOME TAX DEPARTMENT GOVT OF INDIA ABCDE1234F RAHUL SHARMA',
      );

      // 2. Query via DeepDocumentFinderService
      final finder = DeepDocumentFinderService(
        dbService: fakeDb,
      );

      final searchResults = await finder.findDocument('Show my PAN card');

      expect(searchResults, isNotEmpty);
      final match = searchResults.first;
      expect(match.title, contains('PAN Card'));
      expect(match.extractedSummary, contains('ABCDE1234F'));
      expect(match.fileUri, equals('content://docs/pan_card.jpg'));
    });

    test('DeepDocumentFinderService supports Malayalam document search query', () async {
      const picked = PickedDocumentData(
        uri: 'content://docs/passport.jpg',
        filePath: '/cache/vault_uploads/passport.jpg',
        fileName: 'passport.jpg',
        mimeType: 'image/jpeg',
        fileSize: 120000,
      );

      await vaultService.saveToVault(
        pickedData: picked,
        customTitle: 'ഇന്ത്യൻ പാസ്പോർട്ട്',
        customCategory: 'passport',
        extractedText: 'REPUBLIC OF INDIA PASSPORT Z9482014 JOHN DOE',
      );

      final finder = DeepDocumentFinderService(
        dbService: fakeDb,
      );

      final searchResults = await finder.findDocument('എന്റെ പാസ്പോർട്ട് എവിടെ?');

      expect(searchResults, isNotEmpty);
      expect(searchResults.first.fileUri, equals('content://docs/passport.jpg'));
    });

    test('LocalDatabaseService getAllDecryptedNodes and deleteMemoryNode work correctly', () async {
      const picked = PickedDocumentData(
        uri: 'content://docs/doc1.pdf',
        filePath: '/cache/doc1.pdf',
        fileName: 'doc1.pdf',
        mimeType: 'application/pdf',
        fileSize: 5000,
      );

      await vaultService.saveToVault(
        pickedData: picked,
        customTitle: 'Flight Ticket',
        customCategory: 'ticket',
        extractedText: 'Flight AI-505 Cochin to Delhi seat 12B',
      );

      var allNodes = await fakeDb.getAllDecryptedNodes();
      expect(allNodes.length, equals(1));
      expect(allNodes.first.category, equals(MemoryCategory.ocrDoc));

      final deleted = await fakeDb.deleteMemoryNode(allNodes.first.id);
      expect(deleted, isTrue);

      allNodes = await fakeDb.getAllDecryptedNodes();
      expect(allNodes, isEmpty);
    });
  });
}
