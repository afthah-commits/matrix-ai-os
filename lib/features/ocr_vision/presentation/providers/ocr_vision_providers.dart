import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/database/database_providers.dart';
import 'package:matrix_ai_os/features/ai_brain/presentation/providers/ai_brain_providers.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/deep_document_finder_service.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/gallery_ocr_service.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/manual_document_vault_service.dart';

/// Provider for the On-Device Gallery OCR service.
final galleryOcrServiceProvider = Provider<GalleryOcrService>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  final service = GalleryOcrService(dbService: dbService);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for the Deep Document, Passport & PDF Finder Service.
final deepDocumentFinderServiceProvider = Provider<DeepDocumentFinderService>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  final service = DeepDocumentFinderService(dbService: dbService);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for the Manual Document & ID Card Vault Uploader Service.
final manualDocumentVaultServiceProvider = Provider<ManualDocumentVaultService>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  final actionDispatcher = ref.watch(actionDispatcherServiceProvider);
  final service = ManualDocumentVaultService(
    dbService: dbService,
    actionDispatcher: actionDispatcher,
  );
  ref.onDispose(() => service.dispose());
  return service;
});
