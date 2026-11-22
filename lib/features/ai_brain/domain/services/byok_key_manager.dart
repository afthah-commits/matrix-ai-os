import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Supported AI providers for Matrix AI OS.
enum AiProvider {
  gemini('Google Gemini (Free tier)'),
  openAiCompatible('OpenAI Compatible / Custom URL'),
  offlineLocal('100% Offline Local Engine');

  final String displayName;
  const AiProvider(this.displayName);

  static AiProvider fromString(String? value) {
    if (value == null) return AiProvider.gemini;
    for (final p in AiProvider.values) {
      if (p.name == value) return p;
    }
    return AiProvider.gemini;
  }
}

/// Secure Storage Manager for Bring-Your-Own-Key (BYOK) AI credentials
/// and Air-Gapped / Offline settings.
class ByokKeyManager {
  final FlutterSecureStorage _storage;

  static const String _keyGemini = 'byok_gemini_api_key';
  static const String _keyOpenAi = 'byok_openai_api_key';
  static const String _keyOpenAiBaseUrl = 'byok_openai_base_url';
  static const String _keyProvider = 'byok_selected_provider';
  static const String _keyOfflineOnly = 'byok_offline_only_mode';
  static const String _keyLanguage = 'byok_language_preference';

  static const String defaultOpenAiBaseUrl = 'https://api.openai.com/v1';

  ByokKeyManager({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: true,
              ),
            );

  Future<String?> getGeminiApiKey() async {
    return _storage.read(key: _keyGemini);
  }

  Future<void> setGeminiApiKey(String key) async {
    await _storage.write(key: _keyGemini, value: key.trim());
  }

  Future<String?> getOpenAiApiKey() async {
    return _storage.read(key: _keyOpenAi);
  }

  Future<void> setOpenAiApiKey(String key) async {
    await _storage.write(key: _keyOpenAi, value: key.trim());
  }

  Future<String> getOpenAiBaseUrl() async {
    final url = await _storage.read(key: _keyOpenAiBaseUrl);
    if (url == null || url.trim().isEmpty) {
      return defaultOpenAiBaseUrl;
    }
    return url.trim();
  }

  Future<void> setOpenAiBaseUrl(String url) async {
    await _storage.write(key: _keyOpenAiBaseUrl, value: url.trim());
  }

  Future<AiProvider> getSelectedProvider() async {
    final val = await _storage.read(key: _keyProvider);
    return AiProvider.fromString(val);
  }

  Future<void> setSelectedProvider(AiProvider provider) async {
    await _storage.write(key: _keyProvider, value: provider.name);
  }

  Future<bool> isOfflineOnly() async {
    final val = await _storage.read(key: _keyOfflineOnly);
    return val == 'true';
  }

  Future<void> setOfflineOnly(bool offline) async {
    await _storage.write(key: _keyOfflineOnly, value: offline ? 'true' : 'false');
  }

  /// Gets the user's preferred assistant language ('en' for English, 'ml' for Malayalam).
  Future<String> getLanguagePreference() async {
    final lang = await _storage.read(key: _keyLanguage);
    return lang ?? 'en';
  }

  /// Sets the user's preferred assistant language ('en' or 'ml').
  Future<void> setLanguagePreference(String languageCode) async {
    await _storage.write(key: _keyLanguage, value: languageCode);
  }

  Future<void> clearAllKeys() async {
    await _storage.delete(key: _keyGemini);
    await _storage.delete(key: _keyOpenAi);
    await _storage.delete(key: _keyOpenAiBaseUrl);
  }

  /// Returns whether a valid key is set for the currently selected provider.
  Future<bool> hasActiveKey() async {
    if (await isOfflineOnly()) return false;
    final provider = await getSelectedProvider();
    if (provider == AiProvider.offlineLocal) return false;
    if (provider == AiProvider.gemini) {
      final key = await getGeminiApiKey();
      return key != null && key.isNotEmpty;
    } else if (provider == AiProvider.openAiCompatible) {
      final key = await getOpenAiApiKey();
      return key != null && key.isNotEmpty;
    }
    return false;
  }
}
