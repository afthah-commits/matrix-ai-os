import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Service managing Speech-to-Text (STT) mic input and Text-to-Speech (TTS)
/// voice playback using Android native OS engines (zero heavy offline models).
class VoiceAssistantService extends ChangeNotifier {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isSpeechInitialized = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isTtsEnabled = true;
  String _lastRecognizedWords = '';
  String? _errorMessage;

  String _languageCode = 'en';
  String _localeId = 'en_US';
  String _ttsLanguage = 'en-US';

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get isTtsEnabled => _isTtsEnabled;
  String get lastRecognizedWords => _lastRecognizedWords;
  bool get isInitialized => _isSpeechInitialized;
  String? get errorMessage => _errorMessage;
  String get languageCode => _languageCode;
  String get localeId => _localeId;

  /// Changes the assistant voice and listening language ('en' or 'ml').
  Future<void> setLanguage(String code) async {
    _languageCode = code;
    if (code == 'ml') {
      _localeId = 'ml_IN';
      _ttsLanguage = 'ml-IN';
    } else {
      _localeId = 'en_US';
      _ttsLanguage = 'en-US';
    }
    try {
      await _flutterTts.setLanguage(_ttsLanguage);
    } catch (e) {
      debugPrint('[VoiceAssistantService] TTS setLanguage error: $e');
    }
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  VoiceAssistantService() {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
        notifyListeners();
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        notifyListeners();
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('[VoiceAssistantService] TTS initialization error: $e');
    }
  }

  /// Initializes speech recognition engine with permission request.
  Future<bool> initSpeech() async {
    if (_isSpeechInitialized) return true;
    try {
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final req = await Permission.microphone.request();
        if (!req.isGranted) {
          _errorMessage = 'Microphone permission denied. Please enable it in Settings.';
          notifyListeners();
          return false;
        }
      }

      _isSpeechInitialized = await _speechToText.initialize(
        onError: (val) {
          _isListening = false;
          _errorMessage = val.errorMsg;
          notifyListeners();
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            notifyListeners();
          }
        },
      );

      if (!_isSpeechInitialized) {
        _errorMessage = 'Speech recognition service is not available on this device.';
      } else {
        _errorMessage = null;
      }
      notifyListeners();
      return _isSpeechInitialized;
    } catch (e) {
      debugPrint('[VoiceAssistantService] Speech initialization error: $e');
      _errorMessage = 'Speech initialization failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Starts listening to microphone input.
  Future<void> startListening({
    required Function(String text) onResult,
  }) async {
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final req = await Permission.microphone.request();
      if (!req.isGranted) {
        _errorMessage = 'Microphone permission denied. Cannot listen.';
        notifyListeners();
        return;
      }
    }

    if (!_isSpeechInitialized) {
      final ok = await initSpeech();
      if (!ok) return;
    }

    if (_isSpeaking) {
      await stopSpeaking();
    }

    _lastRecognizedWords = '';
    _errorMessage = null;
    _isListening = true;
    notifyListeners();

    try {
      await _speechToText.listen(
        onResult: (result) {
          _lastRecognizedWords = result.recognizedWords;
          notifyListeners();
          if (result.finalResult) {
            _isListening = false;
            notifyListeners();
            onResult(result.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 15),
          pauseFor: const Duration(seconds: 3),
          localeId: _localeId,
        ),
      );
    } catch (e) {
      _isListening = false;
      _errorMessage = 'Microphone listen error: $e';
      notifyListeners();
    }
  }

  /// Stops speech listening session.
  Future<void> stopListening() async {
    if (_isListening) {
      await _speechToText.stop();
      _isListening = false;
      notifyListeners();
    }
  }

  /// Speaks AI response aloud if TTS is enabled.
  Future<void> speak(String text) async {
    if (!_isTtsEnabled) return;
    try {
      // Strip markdown symbols before speaking
      final cleanText = _cleanMarkdownForSpeech(text);
      if (cleanText.isEmpty) return;

      if (_isSpeaking) {
        await _flutterTts.stop();
      }
      await _flutterTts.speak(cleanText);
    } catch (e) {
      debugPrint('[VoiceAssistantService] Speak error: $e');
    }
  }

  /// Stops current speech output.
  Future<void> stopSpeaking() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      _isSpeaking = false;
      notifyListeners();
    }
  }

  /// Toggles spoken voice responses.
  void toggleTts(bool enabled) {
    _isTtsEnabled = enabled;
    if (!enabled && _isSpeaking) {
      stopSpeaking();
    }
    notifyListeners();
  }

  static String _cleanMarkdownForSpeech(String markdown) {
    return markdown
        .replaceAll(RegExp(r'\*\*|\*|#+|`'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1')
        .replaceAll(RegExp(r'\[[A-Z0-9_]+\]'), '') // remove privacy tokens
        .replaceAll(RegExp(r'>'), '')
        .trim();
  }

  @override
  void dispose() {
    _speechToText.stop();
    _flutterTts.stop();
    super.dispose();
  }
}
