import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/models/daily_summary.dart';
import 'package:matrix_ai_os/core/database/models/memory_node.dart';
import 'package:matrix_ai_os/core/security/cipher_service.dart';
import 'package:matrix_ai_os/core/security/encryption_key_manager.dart';
import 'package:matrix_ai_os/objectbox.g.dart';

/// Decrypted representation of a [MemoryNode] for in-memory processing.
class DecryptedMemoryNode {
  final int id;
  final String category;
  final String content;
  final String metadataJson;
  final DateTime timestamp;
  final String? fileUri;
  final bool isPinned;

  const DecryptedMemoryNode({
    required this.id,
    required this.category,
    required this.content,
    required this.metadataJson,
    required this.timestamp,
    this.fileUri,
    required this.isPinned,
  });
}

/// Core Local Database Service for Matrix AI OS.
///
/// Features:
/// - Secure hardware-backed AES-256-GCM encryption of sensitive payloads
/// - ObjectBox local high-speed NoSQL engine
/// - Zero data leakage (all personal content encrypted before disk write)
/// - On-demand database storage size monitoring
class LocalDatabaseService {
  final EncryptionKeyManager _keyManager;
  final CipherService _cipherService;

  Store? _store;
  Box<MemoryNode>? _memoryBox;
  Box<DailySummary>? _summaryBox;
  String? _databaseDirectoryPath;
  bool _isInitialized = false;

  LocalDatabaseService({
    EncryptionKeyManager? keyManager,
    CipherService? cipherService,
  })  : _keyManager = keyManager ?? EncryptionKeyManager(),
        _cipherService = cipherService ?? CipherService();

  bool get isInitialized => _isInitialized && _store != null;
  CipherService get cipherService => _cipherService;
  Box<MemoryNode> get memoryBox {
    _ensureInitialized();
    return _memoryBox!;
  }

  Box<DailySummary> get summaryBox {
    _ensureInitialized();
    return _summaryBox!;
  }

  String? get databasePath => _databaseDirectoryPath;

  /// Initializes the secure keystore key, cipher service, and the ObjectBox store.
  Future<void> initialize({String? customDirectoryPath}) async {
    if (_isInitialized) return;

    try {
      // 1. Retrieve or generate the master 256-bit encryption key
      final masterKey = await _keyManager.getOrCreateMasterKey();
      await _cipherService.initialize(masterKey);

      // 2. Resolve database directory
      if (customDirectoryPath != null) {
        _databaseDirectoryPath = customDirectoryPath;
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        _databaseDirectoryPath = '${docsDir.path}${Platform.pathSeparator}${AppConstants.objectBoxDirName}';
      }

      final dir = Directory(_databaseDirectoryPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 3. Initialize ObjectBox Store
      _store = await openStore(directory: _databaseDirectoryPath);
      _memoryBox = _store!.box<MemoryNode>();
      _summaryBox = _store!.box<DailySummary>();
      _isInitialized = true;

      debugPrint('[LocalDatabaseService] ObjectBox initialized at $_databaseDirectoryPath with AES-256-GCM encryption.');
    } catch (e, stack) {
      debugPrint('[LocalDatabaseService] Initialization failed: $e\n$stack');
      rethrow;
    }
  }

  /// Inserts a new [MemoryNode], automatically encrypting sensitive fields before disk persistence.
  Future<MemoryNode> insertMemoryNode({
    required String category,
    required String content,
    String metadataJson = '',
    DateTime? timestamp,
    String? fileUri,
    bool isPinned = false,
  }) async {
    _ensureInitialized();

    final encryptedContent = await _cipherService.encrypt(content);
    final encryptedMetadata = metadataJson.isNotEmpty
        ? await _cipherService.encrypt(metadataJson)
        : '';

    final node = MemoryNode(
      category: category,
      content: encryptedContent,
      metadataJson: encryptedMetadata,
      timestamp: timestamp ?? DateTime.now(),
      fileUri: fileUri,
      isPinned: isPinned,
    );

    node.id = _memoryBox!.put(node);
    return node;
  }

  /// Decrypts a stored [MemoryNode] into plaintext [DecryptedMemoryNode].
  Future<DecryptedMemoryNode> decryptNode(MemoryNode node) async {
    _ensureInitialized();

    final plainContent = await _cipherService.decrypt(node.content);
    final plainMetadata = node.metadataJson.isNotEmpty
        ? await _cipherService.decrypt(node.metadataJson)
        : '';

    return DecryptedMemoryNode(
      id: node.id,
      category: node.category,
      content: plainContent,
      metadataJson: plainMetadata,
      timestamp: node.timestamp,
      fileUri: node.fileUri,
      isPinned: node.isPinned,
    );
  }

  /// Returns recent memory nodes decrypted for assistant reasoning/UI display.
  Future<List<DecryptedMemoryNode>> getRecentDecryptedNodes({int limit = 50}) async {
    _ensureInitialized();

    final query = (_memoryBox!.query()
          ..order(MemoryNode_.timestamp, flags: Order.descending))
        .build();

    try {
      final rawNodes = query.find().take(limit).toList();
      final decryptedList = <DecryptedMemoryNode>[];
      for (final raw in rawNodes) {
        decryptedList.add(await decryptNode(raw));
      }
      return decryptedList;
    } finally {
      query.close();
    }
  }

  /// Returns total count of stored [MemoryNode] entries.
  int getMemoryNodeCount() {
    _ensureInitialized();
    return _memoryBox!.count();
  }

  /// Returns total count of stored [DailySummary] entries.
  int getDailySummaryCount() {
    _ensureInitialized();
    return _summaryBox!.count();
  }

  /// Calculates the on-disk footprint in bytes of the local ObjectBox database.
  Future<int> getDatabaseSizeInBytes() async {
    if (_databaseDirectoryPath == null) return 0;
    final dir = Directory(_databaseDirectoryPath!);
    if (!await dir.exists()) return 0;

    int totalBytes = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          totalBytes += await entity.length();
        }
      }
    } catch (e) {
      debugPrint('[LocalDatabaseService] Error computing DB size: $e');
    }
    return totalBytes;
  }

  void _ensureInitialized() {
    if (!_isInitialized || _store == null || _memoryBox == null || _summaryBox == null) {
      throw StateError('LocalDatabaseService is not initialized. Call initialize() first.');
    }
  }

  /// Closes the ObjectBox store and releases native locks.
  void close() {
    if (_store != null && !_store!.isClosed()) {
      _store!.close();
      _isInitialized = false;
      debugPrint('[LocalDatabaseService] Store closed.');
    }
  }
}
