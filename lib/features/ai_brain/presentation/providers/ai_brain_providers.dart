import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/database/database_providers.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/knowledge_graph_service.dart';

/// Provider for the On-Device Personal Knowledge Graph engine.
final knowledgeGraphServiceProvider = Provider<KnowledgeGraphService>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  return KnowledgeGraphService(dbService: dbService);
});
