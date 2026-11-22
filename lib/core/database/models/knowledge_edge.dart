import 'package:objectbox/objectbox.dart';

/// Semantic relationship types in the Personal Knowledge Graph.
class KnowledgeRelation {
  KnowledgeRelation._();

  static const String paidTo = 'PAID_TO';
  static const String receivedFrom = 'RECEIVED_FROM';
  static const String called = 'CALLED';
  static const String mentionedInDoc = 'MENTIONED_IN_DOC';
  static const String frequentContact = 'FREQUENT_CONTACT';
  static const String linkedAccount = 'LINKED_ACCOUNT';
  static const String documentId = 'DOCUMENT_ID';
}

/// Represents an edge (relationship) between two entities in the on-device Personal Knowledge Graph.
/// Examples:
/// - (User) -[PAID_TO]-> (Swiggy)
/// - (User) -[CALLED]-> (Mom)
/// - (Passport) -[MENTIONED_IN_DOC]-> (Document #12)
@Entity()
class KnowledgeEdge {
  @Id()
  int id;

  /// Origin node identifier (e.g., "User", "Axis Bank", "Mom", "Passport").
  @Index()
  String sourceEntity;

  /// Semantic relationship type (e.g. PAID_TO, CALLED, MENTIONED_IN_DOC, FREQUENT_CONTACT).
  String relationType;

  /// Destination node identifier (e.g., "Swiggy", "1499.00", "A/c 3948", "Pass_XYZ").
  @Index()
  String targetEntity;

  /// Strength or frequency weight of the association (incremented on recurring occurrences).
  double weight;

  /// AES-256-GCM encrypted context snippet providing provenance/proof of the relation.
  String encryptedContext;

  /// Timestamp when this connection was created or reinforced.
  @Index()
  @Property(type: PropertyType.date)
  DateTime lastUpdated;

  KnowledgeEdge({
    this.id = 0,
    required this.sourceEntity,
    required this.relationType,
    required this.targetEntity,
    this.weight = 1.0,
    this.encryptedContext = '',
    required this.lastUpdated,
  });
}
