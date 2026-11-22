import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/pii_masking_service.dart';

void main() {
  late PiiMaskingService maskingService;

  setUp(() {
    maskingService = PiiMaskingService();
  });

  group('PiiMaskingService Tests', () {
    test('Empty text returns empty payload', () {
      final payload = maskingService.mask('');
      expect(payload.maskedText, isEmpty);
      expect(payload.tokenMap, isEmpty);
      expect(payload.totalTokensMasked, 0);

      final unmasked = maskingService.unmask('', {});
      expect(unmasked, isEmpty);
    });

    test('Masks phone numbers accurately and restores them', () {
      const text =
          'User called +91 98765 43210 and also sent SMS to +1-800-555-0199.';
      final payload = maskingService.mask(text);

      expect(payload.hasMaskedTokens, isTrue);
      expect(payload.maskedText.contains('+91 98765 43210'), isFalse);
      expect(payload.maskedText.contains('+1-800-555-0199'), isFalse);
      expect(payload.maskedText, contains('[PHONE_1]'));
      expect(payload.maskedText, contains('[PHONE_2]'));

      final restored = maskingService.unmask(payload.maskedText, payload.tokenMap);
      expect(restored, equals(text));
    });

    test('Reuses identical tokens for repeated phone numbers', () {
      const text = 'Call 9876543210 immediately. Repeating 9876543210.';
      final payload = maskingService.mask(text);

      expect(payload.totalTokensMasked, equals(1));
      expect(payload.tokenMap.containsKey('[PHONE_1]'), isTrue);
      expect(payload.maskedText, equals('Call [PHONE_1] immediately. Repeating [PHONE_1].'));

      final restored = maskingService.unmask(payload.maskedText, payload.tokenMap);
      expect(restored, equals(text));
    });

    test('Masks Bank Accounts and Card numbers', () {
      const text = 'Debited Rs. 450.00 from A/c **3948. Card: 4111-2222-3333-4444.';
      final payload = maskingService.mask(text);

      expect(payload.maskedText.contains('**3948'), isFalse);
      expect(payload.maskedText.contains('4111-2222-3333-4444'), isFalse);
      expect(payload.maskedText, contains('[ACCOUNT_1]'));
      expect(payload.maskedText, contains('[ACCOUNT_2]'));
      // Ensure transaction amount Rs. 450.00 is NOT touched
      expect(payload.maskedText, contains('Rs. 450.00'));

      final restored = maskingService.unmask(payload.maskedText, payload.tokenMap);
      expect(restored, equals(text));
    });

    test('Masks Passports, PAN cards, and Aadhaar numbers', () {
      const text =
          'Passport: Z9482014, PAN: ABCDE1234F, Aadhaar: 5482 1928 3847.';
      final payload = maskingService.mask(text);

      expect(payload.maskedText.contains('Z9482014'), isFalse);
      expect(payload.maskedText.contains('ABCDE1234F'), isFalse);
      expect(payload.maskedText.contains('5482 1928 3847'), isFalse);
      expect(payload.maskedText, contains('[ID_DOC_1]'));
      expect(payload.maskedText, contains('[ID_DOC_2]'));
      expect(payload.maskedText, contains('[ID_DOC_3]'));

      final restored = maskingService.unmask(payload.maskedText, payload.tokenMap);
      expect(restored, equals(text));
    });

    test('Masks UPI IDs and Email addresses accurately without cross-contamination', () {
      const text =
          'Paid to merchant.store@okaxis and received invoice at alice.smith@matrix.ai.';
      final payload = maskingService.mask(text);

      expect(payload.maskedText.contains('merchant.store@okaxis'), isFalse);
      expect(payload.maskedText.contains('alice.smith@matrix.ai'), isFalse);
      expect(payload.maskedText, contains('[UPI_1]'));
      expect(payload.maskedText, contains('[EMAIL_1]'));

      final restored = maskingService.unmask(payload.maskedText, payload.tokenMap);
      expect(restored, equals(text));
    });

    test('Does not mask currency amounts or dates as phone/account numbers', () {
      const text =
          r'Spent Rs. 450.00 on 2026-11-22 and $1,250.75 on 22/11/2026.';
      final payload = maskingService.mask(text);

      expect(payload.totalTokensMasked, 0);
      expect(payload.maskedText, equals(text));
    });

    test('Restores LLM responses with subtle spacing anomalies in tokens', () {
      final tokenMap = {
        '[PHONE_1]': '+91 98765 43210',
        '[ACCOUNT_1]': '**3948',
      };

      const llmResponse =
          'Your account [ ACCOUNT_1 ] was charged. Call [PHONE_1] if needed.';
      final unmasked = maskingService.unmask(llmResponse, tokenMap);

      expect(unmasked, equals('Your account **3948 was charged. Call +91 98765 43210 if needed.'));
    });
  });
}
