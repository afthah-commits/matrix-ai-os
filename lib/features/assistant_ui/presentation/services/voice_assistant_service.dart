import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
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

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get isTtsEnabled => _isTtsEnabled;
  String get lastRecognizedWords => _lastRecognizedWords;
  bool get isInitialized => _isSpeechInitialized;

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
      _isSpeechInitialized = await _speechToText.initialize(
        onError: (val) {
          _isListening = false;
          notifyListeners();
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            notifyListeners();
          }
        },
      );
      notifyListeners();
      return _isSpeechInitialized;
    } catch (e) {
      debugPrint('[VoiceAssistantService] Speech initialization error: $e');
      return false;
    }
  }

  /// Starts listening to microphone input.
  Future<void> startListening({
    required Function(String text) onResult,
  }) async {
    if (!_isSpeechInitialized) {
      final ok = await initSpeech();
      if (!ok) return;
    }

    if (_isSpeaking) {
      await stopSpeaking();
    }

    _lastRecognizedWords = '';
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
        ),
      );
    } catch (e) {
      _isListening = false;
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
