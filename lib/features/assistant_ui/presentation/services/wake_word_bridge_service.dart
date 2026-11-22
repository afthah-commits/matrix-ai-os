import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Event payload emitted when "Hey Matrix" or system assist intent is triggered.
class WakeWordEvent {
  final String trigger; // 'wake_word', 'assist_intent', 'voice_command'
  final String? initialQuery;

  const WakeWordEvent({
    required this.trigger,
    this.initialQuery,
  });

  @override
  String toString() => 'WakeWordEvent(trigger: $trigger, initialQuery: $initialQuery)';
}

/// Service bridging Flutter to native Android wake-word detection
/// and default digital assistant integration.
class WakeWordBridgeService extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('com.matrixai.os/wake_word');
  static const String _storageKeyEnabled = 'matrix_wake_word_enabled';

  final FlutterSecureStorage _storage;
  final StreamController<WakeWordEvent> _eventController =
      StreamController<WakeWordEvent>.broadcast();

  bool _isServiceRunning = false;
  bool _isWakeWordEnabled = false;
  bool _isInitialized = false;

  bool get isServiceRunning => _isServiceRunning;
  bool get isWakeWordEnabled => _isWakeWordEnabled;
  bool get isInitialized => _isInitialized;
  Stream<WakeWordEvent> get wakeWordEvents => _eventController.stream;

  WakeWordBridgeService({
    FlutterSecureStorage? storage,
    MethodChannel channel = _channel,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
            ) {
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  /// Initializes persisted state and syncs with native service.
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final savedVal = await _storage.read(key: _storageKeyEnabled);
      _isWakeWordEnabled = savedVal == 'true';

      _isServiceRunning = await checkIsRunning();

      // If user previously enabled hands-free wake word but service is not running,
      // attempt to start it.
      if (_isWakeWordEnabled && !_isServiceRunning) {
        await startWakeWordService();
      }
    } catch (e) {
      debugPrint('[WakeWordBridgeService] Init error: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onWakeWordDetected') {
      try {
        final Map<dynamic, dynamic>? args =
            call.arguments as Map<dynamic, dynamic>?;
        final trigger = args?['trigger'] as String? ?? 'wake_word';
        final query = args?['initialQuery'] as String?;

        final event = WakeWordEvent(trigger: trigger, initialQuery: query);
        debugPrint('[WakeWordBridgeService] Wake event received: $event');
        _eventController.add(event);
      } catch (e) {
        debugPrint('[WakeWordBridgeService] Error parsing wake event: $e');
      }
    }
  }

  /// Checks if native foreground service is actively running.
  Future<bool> checkIsRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isWakeWordRunning');
      _isServiceRunning = result ?? false;
      notifyListeners();
      return _isServiceRunning;
    } catch (e) {
      debugPrint('[WakeWordBridgeService] checkIsRunning error: $e');
      return false;
    }
  }

  /// Starts native foreground wake-word listening service.
  Future<bool> startWakeWordService() async {
    try {
      final success =
          await _channel.invokeMethod<bool>('startWakeWordService') ?? false;
      if (success) {
        _isServiceRunning = true;
        _isWakeWordEnabled = true;
        await _storage.write(key: _storageKeyEnabled, value: 'true');
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('[WakeWordBridgeService] startWakeWordService error: $e');
    }
    return false;
  }

  /// Stops native foreground wake-word service.
  Future<bool> stopWakeWordService() async {
    try {
      final success =
          await _channel.invokeMethod<bool>('stopWakeWordService') ?? false;
      if (success) {
        _isServiceRunning = false;
        _isWakeWordEnabled = false;
        await _storage.write(key: _storageKeyEnabled, value: 'false');
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('[WakeWordBridgeService] stopWakeWordService error: $e');
    }
    return false;
  }

  /// Opens Android OS Voice & Default Assistant settings.
  Future<bool> openDefaultAssistantSettings() async {
    try {
      final success =
          await _channel.invokeMethod<bool>('openDefaultAssistantSettings') ??
              false;
      return success;
    } catch (e) {
      debugPrint('[WakeWordBridgeService] openDefaultAssistantSettings error: $e');
      return false;
    }
  }

  /// Informs native wake-word service to pause listening when Flutter mic is active.
  Future<void> notifyVoiceStarted() async {
    try {
      await _channel.invokeMethod('onFlutterVoiceStarted');
    } catch (e) {
      debugPrint('[WakeWordBridgeService] notifyVoiceStarted error: $e');
    }
  }

  /// Informs native wake-word service to resume listening when Flutter mic completes.
  Future<void> notifyVoiceStopped() async {
    try {
      await _channel.invokeMethod('onFlutterVoiceStopped');
    } catch (e) {
      debugPrint('[WakeWordBridgeService] notifyVoiceStopped error: $e');
    }
  }

  @override
  void dispose() {
    _eventController.close();
    super.dispose();
  }
}
