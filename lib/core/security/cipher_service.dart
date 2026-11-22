import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Service responsible for field-level authenticated AES-256-GCM encryption
/// and decryption of sensitive local memory nodes and personal logs.
class CipherService {
  final AesGcm _algorithm = AesGcm.with256bits();
  SecretKey? _secretKey;

  /// Initializes the cipher service with the 32-byte master key.
  Future<void> initialize(Uint8List masterKeyBytes) async {
    _secretKey = SecretKey(masterKeyBytes);
  }

  /// Whether the cipher is initialized with an active secret key.
  bool get isInitialized => _secretKey != null;

  /// Encrypts plaintext using AES-256-GCM.
  /// Returns a Base64-encoded string combining nonce, ciphertext, and 128-bit MAC tag.
  Future<String> encrypt(String plaintext) async {
    if (plaintext.isEmpty) return '';
    final key = _secretKey;
    if (key == null) {
      throw StateError('CipherService is not initialized. Call initialize() first.');
    }

    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );

    // Concatenates nonce (12 bytes) + ciphertext + MAC (16 bytes)
    final concatenated = secretBox.concatenation();
    return base64Encode(concatenated);
  }

  /// Decrypts a Base64-encoded payload produced by [encrypt].
  Future<String> decrypt(String encryptedBase64) async {
    if (encryptedBase64.isEmpty) return '';
    final key = _secretKey;
    if (key == null) {
      throw StateError('CipherService is not initialized. Call initialize() first.');
    }

    try {
      final concatenated = base64Decode(encryptedBase64);
      final secretBox = SecretBox.fromConcatenation(
        concatenated,
        nonceLength: _algorithm.nonceLength,
        macLength: _algorithm.macAlgorithm.macLength,
      );

      final decryptedBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: key,
      );
      return utf8.decode(decryptedBytes);
    } catch (e) {
      throw StateError('Decryption failed. Data might be corrupted or key mismatch: $e');
    }
  }
}
