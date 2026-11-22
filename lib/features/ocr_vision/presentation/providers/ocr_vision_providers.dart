import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/database/database_providers.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/gallery_ocr_service.dart';

/// Provider for the On-Device Gallery OCR service.
final galleryOcrServiceProvider = Provider<GalleryOcrService>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  final service = GalleryOcrService(dbService: dbService);
  ref.onDispose(() => service.dispose());
  return service;
});
