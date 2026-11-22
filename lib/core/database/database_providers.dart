import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/core/database/storage_pruner_service.dart';
import 'package:matrix_ai_os/core/security/cipher_service.dart';
import 'package:matrix_ai_os/core/security/encryption_key_manager.dart';

/// Provider for the hardware-backed encryption key manager.
final encryptionKeyManagerProvider = Provider<EncryptionKeyManager>((ref) {
  return EncryptionKeyManager();
});

/// Provider for the AES-256-GCM cipher service.
final cipherServiceProvider = Provider<CipherService>((ref) {
  return CipherService();
});

/// Core singleton provider for the encrypted Local Database Service.
final localDatabaseServiceProvider = Provider<LocalDatabaseService>((ref) {
  final keyManager = ref.watch(encryptionKeyManagerProvider);
  final cipherService = ref.watch(cipherServiceProvider);
  return LocalDatabaseService(
    keyManager: keyManager,
    cipherService: cipherService,
  );
});

/// Provider for the rolling data retention & pruning service.
final storagePrunerServiceProvider = Provider<StoragePrunerService>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  return StoragePrunerService(dbService: dbService);
});
