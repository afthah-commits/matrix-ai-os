import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/models/knowledge_edge.dart';
import 'package:matrix_ai_os/core/database/models/memory_node.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/models/document_classification.dart';

void main() {
  group('Personal Knowledge Graph & Immunity Tests', () {
    test('KnowledgeRelation constants are correctly defined', () {
      expect(KnowledgeRelation.paidTo, equals('PAID_TO'));
      expect(KnowledgeRelation.receivedFrom, equals('RECEIVED_FROM'));
      expect(KnowledgeRelation.called, equals('CALLED'));
      expect(KnowledgeRelation.mentionedInDoc, equals('MENTIONED_IN_DOC'));
      expect(KnowledgeRelation.frequentContact, equals('FREQUENT_CONTACT'));
      expect(KnowledgeRelation.linkedAccount, equals('LINKED_ACCOUNT'));
      expect(KnowledgeRelation.documentId, equals('DOCUMENT_ID'));
    });

    test('KnowledgeEdge model initializes with default weight of 1.0', () {
      final edge = KnowledgeEdge(
        sourceEntity: 'User',
        relationType: KnowledgeRelation.paidTo,
        targetEntity: 'Swiggy',
        lastUpdated: DateTime.now(),
      );

      expect(edge.weight, equals(1.0));
      expect(edge.sourceEntity, equals('User'));
      expect(edge.targetEntity, equals('Swiggy'));
    });

    test('OCR Document category is strictly immune from auto-pruning rules', () {
      // 1. Verify app constant immunity set
      expect(MemoryCategory.immuneFromPruning.contains(MemoryCategory.ocrDoc), isTrue);

      // 2. Simulated pruner filter logic verification
      final expiredNodes = [
        MemoryNode(
          id: 1,
          category: MemoryCategory.transaction,
          content: 'Old transaction',
          timestamp: DateTime.now().subtract(const Duration(days: 40)),
          isPinned: false,
        ),
        MemoryNode(
          id: 2,
          category: MemoryCategory.ocrDoc,
          content: 'Passport Document OCR',
          timestamp: DateTime.now().subtract(const Duration(days: 45)),
          isPinned: true, // Permanent knowledge
        ),
        MemoryNode(
          id: 3,
          category: MemoryCategory.screenTime,
          content: 'Old screen time',
          timestamp: DateTime.now().subtract(const Duration(days: 35)),
          isPinned: false,
        ),
      ];

      // Pruning filter rule: only prune nodes that are NOT pinned AND not in immuneFromPruning
      final prunable = expiredNodes.where((node) {
        return !node.isPinned && !MemoryCategory.immuneFromPruning.contains(node.category);
      }).toList();

      expect(prunable.length, equals(2));
      expect(prunable.map((n) => n.id), containsAll([1, 3]));
      expect(prunable.map((n) => n.id), isNot(contains(2)));
    });

    test('DocumentClassification serialization preserves all entities and types', () {
      const entities = ExtractedEntities(
        idNumber: 'P1234567',
        amount: 450.00,
        dates: ['2026-11-22'],
        merchantOrIssuer: 'Blue Tokai',
      );

      const classification = DocumentClassification(
        type: DocumentType.invoiceReceipt,
        confidence: 0.92,
        entities: entities,
        summary: 'Receipt test',
      );

      final map = classification.toMap();
      final restored = DocumentClassification.fromMap(map);

      expect(restored.type, equals(DocumentType.invoiceReceipt));
      expect(restored.confidence, equals(0.92));
      expect(restored.entities.idNumber, equals('P1234567'));
      expect(restored.entities.amount, equals(450.00));
      expect(restored.entities.merchantOrIssuer, equals('Blue Tokai'));
    });
  });
}
