import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/offline_slm_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late OfflineSlmManager slmManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('matrix_slm_test_');
    slmManager = OfflineSlmManager(
      customStorageDir: tempDir.path,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('OfflineSlmManager Tests', () {
    test('Catalog contains expected models with strict format and sizes', () {
      expect(OfflineSlmManager.catalog, isNotEmpty);
      final gemma = OfflineSlmManager.catalog.firstWhere((m) => m.id == 'gemma_2b_it');
      expect(gemma.name, contains('Gemma-2B-IT'));
      expect(gemma.sizeFormatted, contains('1.27 GB'));

      final smolLm = OfflineSlmManager.catalog.firstWhere((m) => m.id == 'smollm_360m');
      expect(smolLm.name, contains('SmolLM-360M'));
      expect(smolLm.sizeFormatted, contains('220 MB'));
    });

    test('Storage Guardrail: Rejects download when device disk space is insufficient', () {
      final model = OfflineSlmManager.catalog.first;

      // When free storage is below required threshold (model size + 500MB buffer)
      const lowStorage = 500 * 1024 * 1024; // 500MB
      final canDownload = slmManager.hasSufficientStorage(
        model: model,
        availableBytes: lowStorage,
      );
      expect(canDownload, isFalse);

      // When free storage is plenty (e.g. 5GB)
      const highStorage = 5 * 1024 * 1024 * 1024;
      final canDownloadHigh = slmManager.hasSufficientStorage(
        model: model,
        availableBytes: highStorage,
      );
      expect(canDownloadHigh, isTrue);
    });

    test('Downloads model with stream progress and creates file on disk', () async {
      final model = SlmModelInfo(
        id: 'test_micro_model',
        name: 'Test Micro Model',
        description: 'Mock model for tests',
        sizeBytes: 100,
        downloadUrl: 'https://example.com/test_model.bin',
        sha256Checksum: 'dummy_hash',
        minRequiredStorageBytes: 200,
      );

      final mockClient = MockClient((request) async {
        return http.Response(
          List.generate(100, (i) => i % 256).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          200,
          headers: {'content-length': '100'},
        );
      });

      final manager = OfflineSlmManager(
        client: mockClient,
        customStorageDir: tempDir.path,
      );

      final progressValues = <double>[];
      await for (final p in manager.downloadModel(model, mockAvailableStorage: 10000)) {
        progressValues.add(p);
      }

      expect(progressValues, isNotEmpty);
      expect(progressValues.last, equals(1.0));

      final state = manager.getModelState('test_micro_model');
      expect(state.status, equals(SlmStatus.downloaded));

      // Verify file exists on disk
      final file = await manager.getModelFile('test_micro_model');
      expect(await file.exists(), isTrue);

      // Verify deleteModel reclaims storage immediately
      final deleted = await manager.deleteModel('test_micro_model');
      expect(deleted, isTrue);
      expect(await file.exists(), isFalse);
      expect(manager.getModelState('test_micro_model').status, equals(SlmStatus.notDownloaded));
    });

    test('SmartRuleBasedFallbackEngine provides structured offline reasoning with zero weights', () async {
      final engine = SmartRuleBasedFallbackEngine();
      final output = await engine.generate(
        prompt: 'Analyze my spending trends',
        context: 'Decrypted Context: Spent \$450 on Groceries at Axis Bank',
      );

      expect(output, contains('Local Reasoning Core (Air-Gapped)'));
      expect(output, contains('Spent \$450 on Groceries'));
      expect(output, contains('Addressing: "Analyze my spending trends"'));
    });
  });
}
