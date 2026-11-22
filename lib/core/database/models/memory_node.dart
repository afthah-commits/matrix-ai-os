import 'package:objectbox/objectbox.dart';

/// Represents an individual atomic memory or log ingested into Matrix AI OS.
/// All sensitive payload data (content, metadataJson) is stored encrypted on disk.
@Entity()
class MemoryNode {
  /// ObjectBox auto-increment primary key (0 means unassigned).
  @Id()
  int id;

  /// High-level category: transaction, screen_time, call_log, ocr_doc, note.
  @Index()
  String category;

  /// AES-256-GCM encrypted content string.
  String content;

  /// AES-256-GCM encrypted JSON metadata string (or empty if none).
  String metadataJson;

  /// Timestamp when the memory was captured or logged.
  @Index()
  @Property(type: PropertyType.date)
  DateTime timestamp;

  /// Optional URI referencing external file on device storage (e.g., photo in gallery),
  /// avoiding duplicating large binaries in the database.
  String? fileUri;

  /// Whether this memory is pinned by user or system to protect it from rolling auto-pruning.
  bool isPinned;

  MemoryNode({
    this.id = 0,
    required this.category,
    required this.content,
    this.metadataJson = '',
    required this.timestamp,
    this.fileUri,
    this.isPinned = false,
  });
}
