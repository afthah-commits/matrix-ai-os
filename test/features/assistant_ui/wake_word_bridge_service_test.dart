import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/services/wake_word_bridge_service.dart';

class MockSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _mockData = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _mockData[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _mockData[key] = value;
    } else {
      _mockData.remove(key);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.matrixai.os/wake_word');
  late MockSecureStorage mockStorage;
  late WakeWordBridgeService service;
  final List<MethodCall> methodCalls = [];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      methodCalls.add(call);
      switch (call.method) {
        case 'isWakeWordRunning':
          return true;
        case 'startWakeWordService':
          return true;
        case 'stopWakeWordService':
          return true;
        case 'openDefaultAssistantSettings':
          return true;
        case 'onFlutterVoiceStarted':
          return true;
        case 'onFlutterVoiceStopped':
          return true;
        default:
          return null;
      }
    });

    mockStorage = MockSecureStorage();
    service = WakeWordBridgeService(storage: mockStorage);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    service.dispose();
  });

  group('WakeWordBridgeService Tests', () {
    test('WakeWordEvent creates properly and outputs formatted string', () {
      const event = WakeWordEvent(
        trigger: 'wake_word',
        initialQuery: 'what is my schedule',
      );
      expect(event.trigger, equals('wake_word'));
      expect(event.initialQuery, equals('what is my schedule'));
      expect(event.toString(), contains('what is my schedule'));
    });

    test('checkIsRunning queries native channel and updates state', () async {
      final isRunning = await service.checkIsRunning();
      expect(isRunning, isTrue);
      expect(service.isServiceRunning, isTrue);
      expect(methodCalls.any((call) => call.method == 'isWakeWordRunning'), isTrue);
    });

    test('startWakeWordService invokes native service and writes to storage', () async {
      final result = await service.startWakeWordService();
      expect(result, isTrue);
      expect(service.isServiceRunning, isTrue);
      expect(service.isWakeWordEnabled, isTrue);
      expect(
        methodCalls.any((call) => call.method == 'startWakeWordService'),
        isTrue,
      );
      final stored = await mockStorage.read(key: 'matrix_wake_word_enabled');
      expect(stored, equals('true'));
    });

    test('stopWakeWordService invokes native service and updates storage', () async {
      final result = await service.stopWakeWordService();
      expect(result, isTrue);
      expect(service.isServiceRunning, isFalse);
      expect(service.isWakeWordEnabled, isFalse);
      expect(
        methodCalls.any((call) => call.method == 'stopWakeWordService'),
        isTrue,
      );
      final stored = await mockStorage.read(key: 'matrix_wake_word_enabled');
      expect(stored, equals('false'));
    });

    test('openDefaultAssistantSettings forwards to native intent handler', () async {
      final ok = await service.openDefaultAssistantSettings();
      expect(ok, isTrue);
      expect(
        methodCalls.any((call) => call.method == 'openDefaultAssistantSettings'),
        isTrue,
      );
    });

    test('notifyVoiceStarted and notifyVoiceStopped notify native listener', () async {
      await service.notifyVoiceStarted();
      await service.notifyVoiceStopped();
      expect(
        methodCalls.any((call) => call.method == 'onFlutterVoiceStarted'),
        isTrue,
      );
      expect(
        methodCalls.any((call) => call.method == 'onFlutterVoiceStopped'),
        isTrue,
      );
    });

    test('emits WakeWordEvent on incoming native onWakeWordDetected call', () async {
      WakeWordEvent? receivedEvent;
      final sub = service.wakeWordEvents.listen((event) {
        receivedEvent = event;
      });

      // Simulate native call arriving into Flutter
      final message = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onWakeWordDetected', {
          'trigger': 'wake_word',
          'initialQuery': 'open camera',
        }),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.matrixai.os/wake_word', message, (data) {});

      await pumpEventQueue();

      expect(receivedEvent, isNotNull);
      expect(receivedEvent!.trigger, equals('wake_word'));
      expect(receivedEvent!.initialQuery, equals('open camera'));

      await sub.cancel();
    });
  });
}
