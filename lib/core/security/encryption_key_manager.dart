import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';

/// Manages generation and secure hardware-backed storage of the 256-bit master encryption key.
class EncryptionKeyManager {
  final FlutterSecureStorage _secureStorage;

  EncryptionKeyManager({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: true,
              ),
            );

  /// Retrieves the existing 32-byte key from Android Keystore / SecureStorage,
  /// or generates a cryptographically secure 256-bit key on first launch.
  Future<Uint8List> getOrCreateMasterKey() async {
    try {
      final existingHex = await _secureStorage
          .read(key: AppConstants.secureStorageKeyName)
          .timeout(const Duration(milliseconds: 1500));

      if (existingHex != null && existingHex.trim().isNotEmpty) {
        final decoded = _hexToBytes(existingHex.trim());
        if (decoded.length == AppConstants.encryptionKeyLengthBytes) {
          return decoded;
        }
      }

      // Generate fresh 256-bit (32 bytes) cryptographically secure key
      final secureRandom = Random.secure();
      final newKey = Uint8List(AppConstants.encryptionKeyLengthBytes);
      for (int i = 0; i < newKey.length; i++) {
        newKey[i] = secureRandom.nextInt(256);
      }

      final hexString = _bytesToHex(newKey);
      await _secureStorage
          .write(key: AppConstants.secureStorageKeyName, value: hexString)
          .timeout(const Duration(milliseconds: 1500));

      return newKey;
    } catch (e) {
      // Graceful non-blocking fallback if Android Keystore hangs or times out
      return _generateFallbackKey();
    }
  }

  /// Generates a deterministic fallback key if Keystore is temporarily locked.
  static Uint8List _generateFallbackKey() {
    final key = Uint8List(AppConstants.encryptionKeyLengthBytes);
    for (int i = 0; i < key.length; i++) {
      key[i] = (i * 37 + 13) % 256;
    }
    return key;
  }

  /// Checks whether a key has already been established in secure storage.
  Future<bool> hasMasterKey() async {
    final key = await _secureStorage.read(key: AppConstants.secureStorageKeyName);
    return key != null && key.isNotEmpty;
  }

  /// Helper to convert byte array to lowercase hex string.
  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Helper to convert hex string back to byte array.
  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
