import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/core/database/models/knowledge_edge.dart';
import 'package:matrix_ai_os/core/database/models/memory_node.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/models/document_classification.dart';

/// Decrypted in-memory representation of a KnowledgeEdge.
class DecryptedKnowledgeEdge {
  final int id;
  final String sourceEntity;
  final String relationType;
  final String targetEntity;
  final double weight;
  final String context;
  final DateTime lastUpdated;

  const DecryptedKnowledgeEdge({
    required this.id,
    required this.sourceEntity,
    required this.relationType,
    required this.targetEntity,
    required this.weight,
    required this.context,
    required this.lastUpdated,
  });
}

/// Query result representing contextual memory recall across Knowledge Graph and nodes.
class KnowledgeQueryResult {
  final String query;
  final List<DecryptedKnowledgeEdge> edges;
  final List<DecryptedMemoryNode> memories;
  final double relevanceScore;

  const KnowledgeQueryResult({
    required this.query,
    required this.edges,
    required this.memories,
    required this.relevanceScore,
  });

  bool get isEmpty => edges.isEmpty && memories.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

/// On-Device Personal Knowledge Graph Engine.
///
/// Builds semantic connections between People, Merchants, Documents, Dates, and Transactions
/// without leaking unencrypted data or using heavy cloud graph databases.
class KnowledgeGraphService {
  final LocalDatabaseService _dbService;

  KnowledgeGraphService({required LocalDatabaseService dbService})
      : _dbService = dbService;

  /// Analyzes an ingested [MemoryNode], extracts relational entities,
  /// and updates on-device [KnowledgeEdge] graph links.
  Future<List<KnowledgeEdge>> buildConnectionsForMemory(MemoryNode node) async {
    final edgesCreated = <KnowledgeEdge>[];

    try {
      final decrypted = await _dbService.decryptNode(node);

      switch (node.category) {
        case MemoryCategory.transaction:
          edgesCreated.addAll(await _processTransactionMemory(decrypted));
          break;

        case MemoryCategory.callLog:
          edgesCreated.addAll(await _processCallLogMemory(decrypted));
          break;

        case MemoryCategory.ocrDoc:
          edgesCreated.addAll(await _processOcrDocMemory(decrypted));
          break;

        default:
          break;
      }
    } catch (e) {
      debugPrint('[KnowledgeGraphService] Error building graph connections: $e');
    }

    return edgesCreated;
  }

  Future<List<KnowledgeEdge>> _processTransactionMemory(DecryptedMemoryNode node) async {
    final edges = <KnowledgeEdge>[];
    if (node.metadataJson.isEmpty) return edges;

    try {
      final map = jsonDecode(node.metadataJson) as Map<String, dynamic>;
      final merchant = map['merchant'] as String? ?? '';
      final amount = (map['amount'] as num?)?.toDouble() ?? 0.0;
      final type = map['txType'] as String? ?? 'debit';
      final accountRef = map['accountRef'] as String? ?? '';

      if (merchant.isNotEmpty && merchant.toLowerCase() != 'unknown merchant') {
        final rel = type == 'credit' ? KnowledgeRelation.receivedFrom : KnowledgeRelation.paidTo;
        final edge = await _dbService.upsertEdge(
          sourceEntity: 'User',
          relationType: rel,
          targetEntity: merchant,
          weightDelta: 1.0,
          context: node.content,
        );
        edges.add(edge);

        if (accountRef.isNotEmpty) {
          final accEdge = await _dbService.upsertEdge(
            sourceEntity: merchant,
            relationType: KnowledgeRelation.linkedAccount,
            targetEntity: accountRef,
            weightDelta: 1.0,
            context: 'Account $accountRef used with $merchant (Amt: \$$amount)',
          );
          edges.add(accEdge);
        }
      }
    } catch (_) {}

    return edges;
  }

  Future<List<KnowledgeEdge>> _processCallLogMemory(DecryptedMemoryNode node) async {
    final edges = <KnowledgeEdge>[];
    if (node.metadataJson.isEmpty) return edges;

    try {
      final map = jsonDecode(node.metadataJson) as Map<String, dynamic>;
      final contact = map['contactName'] as String? ?? map['number'] as String? ?? '';

      if (contact.isNotEmpty) {
        final edge = await _dbService.upsertEdge(
          sourceEntity: 'User',
          relationType: KnowledgeRelation.called,
          targetEntity: contact,
          weightDelta: 1.0,
          context: node.content,
        );
        edges.add(edge);

        // If high frequency of calls, record frequentContact
        if (edge.weight >= 5.0) {
          final freqEdge = await _dbService.upsertEdge(
            sourceEntity: 'User',
            relationType: KnowledgeRelation.frequentContact,
            targetEntity: contact,
            weightDelta: 1.0,
            context: 'Frequent contact: ${edge.weight.toInt()} calls logged',
          );
          edges.add(freqEdge);
        }
      }
    } catch (_) {}

    return edges;
  }

  Future<List<KnowledgeEdge>> _processOcrDocMemory(DecryptedMemoryNode node) async {
    final edges = <KnowledgeEdge>[];
    if (node.metadataJson.isEmpty) return edges;

    try {
      final map = jsonDecode(node.metadataJson) as Map<String, dynamic>;
      final classificationMap = map['classification'] as Map<String, dynamic>?;

      if (classificationMap != null) {
        final classification = DocumentClassification.fromMap(classificationMap);
        final docTypeName = classification.type.displayName;

        // 1. Link Document ID number
        if (classification.entities.idNumber != null &&
            classification.entities.idNumber!.isNotEmpty) {
          final idEdge = await _dbService.upsertEdge(
            sourceEntity: docTypeName,
            relationType: KnowledgeRelation.documentId,
            targetEntity: classification.entities.idNumber!,
            weightDelta: 1.0,
            context: classification.summary,
          );
          edges.add(idEdge);
        }

        // 2. Link Merchant / Issuer
        if (classification.entities.merchantOrIssuer != null &&
            classification.entities.merchantOrIssuer!.isNotEmpty) {
          final issuerEdge = await _dbService.upsertEdge(
            sourceEntity: classification.entities.merchantOrIssuer!,
            relationType: KnowledgeRelation.mentionedInDoc,
            targetEntity: docTypeName,
            weightDelta: 1.0,
            context: classification.summary,
          );
          edges.add(issuerEdge);
        }
      }
    } catch (_) {}

    return edges;
  }

  /// Fast local graph & memory query for Phase 4's RAG pipeline.
  /// Finds relevant graph edges and matching encrypted memory nodes.
  Future<KnowledgeQueryResult> queryRelatedMemories(
    String query, {
    int limit = 10,
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) {
      return KnowledgeQueryResult(
        query: query,
        edges: const [],
        memories: const [],
        relevanceScore: 0.0,
      );
    }

    final edgeBox = _dbService.edgeBox;

    // 1. Query KnowledgeEdge matching query term in source or target
    final allEdges = edgeBox.getAll();
    final matchingEdges = allEdges.where((e) {
      return e.sourceEntity.toLowerCase().contains(cleanQuery) ||
          e.targetEntity.toLowerCase().contains(cleanQuery) ||
          e.relationType.toLowerCase().contains(cleanQuery);
    }).take(limit).toList();

    // Decrypt edge context
    final decryptedEdges = <DecryptedKnowledgeEdge>[];
    for (final e in matchingEdges) {
      final ctx = await _dbService.decryptEdgeContext(e);
      decryptedEdges.add(
        DecryptedKnowledgeEdge(
          id: e.id,
          sourceEntity: e.sourceEntity,
          relationType: e.relationType,
          targetEntity: e.targetEntity,
          weight: e.weight,
          context: ctx,
          lastUpdated: e.lastUpdated,
        ),
      );
    }

    // 2. Query recent MemoryNodes and check decrypted matches
    final recentMemories = await _dbService.getRecentDecryptedNodes(limit: 50);
    final matchingMemories = recentMemories.where((m) {
      return m.content.toLowerCase().contains(cleanQuery) ||
          m.category.toLowerCase().contains(cleanQuery) ||
          m.metadataJson.toLowerCase().contains(cleanQuery);
    }).take(limit).toList();

    final score = (decryptedEdges.length * 1.5 + matchingMemories.length).clamp(0.0, 10.0);

    return KnowledgeQueryResult(
      query: query,
      edges: decryptedEdges,
      memories: matchingMemories,
      relevanceScore: score,
    );
  }
}
