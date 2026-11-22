import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/core/security/cipher_service.dart';

void main() {
  group('CipherService Tests', () {
    late CipherService cipherService;
    late Uint8List testKey;

    setUp(() async {
      cipherService = CipherService();
      // 32-byte (256-bit) test key
      testKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      await cipherService.initialize(testKey);
    });

    test('isInitialized returns true after initialize', () {
      expect(cipherService.isInitialized, isTrue);
    });

    test('encrypt produces Base64 ciphertext different from plaintext', () async {
      const plaintext = 'Secret medical and transaction info: \$450.00';
      final encrypted = await cipherService.encrypt(plaintext);

      expect(encrypted, isNotEmpty);
      expect(encrypted, isNot(equals(plaintext)));
    });

    test('decrypt reverses encrypt correctly (Confidentiality & Integrity)', () async {
      const original = 'Personal Private Note 123! @#\$%';
      final encrypted = await cipherService.encrypt(original);
      final decrypted = await cipherService.decrypt(encrypted);

      expect(decrypted, equals(original));
    });

    test('encrypting twice yields different ciphertexts (Random Nonce per encryption)', () async {
      const plaintext = 'Identical input text';
      final enc1 = await cipherService.encrypt(plaintext);
      final enc2 = await cipherService.encrypt(plaintext);

      expect(enc1, isNot(equals(enc2)));

      expect(await cipherService.decrypt(enc1), equals(plaintext));
      expect(await cipherService.decrypt(enc2), equals(plaintext));
    });

    test('handling empty string returns empty string', () async {
      expect(await cipherService.encrypt(''), equals(''));
      expect(await cipherService.decrypt(''), equals(''));
    });
  });
}
