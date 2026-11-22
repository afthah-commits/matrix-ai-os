import 'package:flutter/foundation.dart';

/// Holds the masked text along with the bidirectional token mapping
/// necessary to restore sensitive PII locally on-device.
@immutable
class MaskedPayload {
  final String maskedText;
  final Map<String, String> tokenMap; // e.g. {'[PHONE_1]': '+91 9876543210'}
  final int totalTokensMasked;

  const MaskedPayload({
    required this.maskedText,
    required this.tokenMap,
    required this.totalTokensMasked,
  });

  bool get hasMaskedTokens => totalTokensMasked > 0;

  @override
  String toString() =>
      'MaskedPayload(tokensMasked: $totalTokensMasked, text: $maskedText)';
}

/// Deterministic, zero-leakage on-device PII Masking & Restoration Engine.
///
/// Ensures that zero personal identifiers (Phone numbers, Bank accounts,
/// Passports/Aadhaar/PAN, UPI IDs, Emails) escape to cloud LLMs unredacted.
class PiiMaskingService {
  // Regex definitions
  // 1. Email Address: username@domain.tld (requires dot in domain part)
  static final RegExp _emailRegex = RegExp(
    r'\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b',
    caseSensitive: false,
  );

  // 2. UPI ID: username@bankhandle (no dot in domain part, e.g. john@okaxis, user@upi, shop@paytm)
  static final RegExp _upiRegex = RegExp(
    r'\b[a-zA-Z0-9._\-]{2,64}@[a-zA-Z0-9]{2,30}\b(?!\.[a-zA-Z])',
    caseSensitive: false,
  );

  // 3. Indian / Global Passport: 1 uppercase letter followed by 7 digits (e.g. Z9482014, A1234567)
  static final RegExp _passportRegex = RegExp(
    r'\b[A-Z][0-9]{7}\b',
  );

  // 4. PAN Card: 5 uppercase letters, 4 digits, 1 uppercase letter (e.g. ABCDE1234F)
  static final RegExp _panRegex = RegExp(
    r'\b[A-Z]{5}[0-9]{4}[A-Z]\b',
  );

  // 5. Aadhaar: 12 digits, often formatted as 4-4-4 (e.g. 1234 5678 9012 or 123456789012)
  static final RegExp _aadhaarRegex = RegExp(
    r'\b[2-9][0-9]{3}[\s\-]?[0-9]{4}[\s\-]?[0-9]{4}\b',
  );

  // 6. Bank Account & Card Numbers:
  // Masked account notations: A/c **3948, A/c XX1234, **1234, or explicit 9-18 digit account numbers
  static final RegExp _maskedAccountRegex = RegExp(
    r'(?:a/c|acc|account|card)\s*(?:no\.?|number|ending in|ending)?\s*[:\s]*(\*+[0-9]{3,4}|[xX]+[0-9]{3,4})',
    caseSensitive: false,
  );

  static final RegExp _standaloneMaskedCardRegex = RegExp(
    r'\b(?:\*+|[xX]{2,})[0-9]{3,4}\b',
  );

  static final RegExp _explicitAccountNoRegex = RegExp(
    r'(?:a/c|acc|account|card)\s*(?:no\.?|number)?\s*[:\s#]*([0-9]{9,18})\b',
    caseSensitive: false,
  );

  // 16-digit credit/debit card numbers with dashes or spaces
  static final RegExp _creditCardRegex = RegExp(
    r'\b[0-9]{4}[\s\-][0-9]{4}[\s\-][0-9]{4}[\s\-][0-9]{4}\b',
  );

  // 7. Phone Numbers:
  // Indian mobile with +91 or standalone 10 digits starting with 6-9,
  // or international numbers with + prefix
  static final RegExp _indianPhoneRegex = RegExp(
    r'(?:\+91[\s\-]?)?[6-9][0-9]{4}[\s\-]?[0-9]{5}\b',
  );

  static final RegExp _internationalPhoneRegex = RegExp(
    r'\+[1-9][0-9]{0,2}[\s\-]?(?:\([0-9]{2,4}\)[\s\-]?)?[0-9]{3,4}[\s\-]?[0-9]{3,4}\b',
  );

  /// Masks all personal identifiers in [rawText] into reversible tokens.
  MaskedPayload mask(String rawText) {
    if (rawText.trim().isEmpty) {
      return const MaskedPayload(
        maskedText: '',
        tokenMap: {},
        totalTokensMasked: 0,
      );
    }

    String currentText = rawText;
    final tokenMap = <String, String>{}; // '[PHONE_1]' -> '+91 9876543210'
    final reverseMap = <String, String>{}; // '+91 9876543210' -> '[PHONE_1]'

    int phoneCounter = 1;
    int accountCounter = 1;
    int idCounter = 1;
    int upiCounter = 1;
    int emailCounter = 1;

    // Helper to assign a token or reuse an existing token if the exact value already occurred
    String assignToken(String prefix, int counter, String rawValue) {
      final trimmed = rawValue.trim();
      if (reverseMap.containsKey(trimmed)) {
        return reverseMap[trimmed]!;
      }
      final token = '[$prefix$counter]';
      tokenMap[token] = trimmed;
      reverseMap[trimmed] = token;
      return token;
    }

    // Step 1: Mask Email Addresses first
    currentText = currentText.replaceAllMapped(_emailRegex, (m) {
      final raw = m.group(0)!;
      final token = assignToken('EMAIL_', emailCounter, raw);
      if (token == '[EMAIL_$emailCounter]') emailCounter++;
      return token;
    });

    // Step 2: Mask UPI IDs (handles without dot domain, e.g. user@okaxis)
    currentText = currentText.replaceAllMapped(_upiRegex, (m) {
      final raw = m.group(0)!;
      final token = assignToken('UPI_', upiCounter, raw);
      if (token == '[UPI_$upiCounter]') upiCounter++;
      return token;
    });

    // Step 3: Mask Bank Accounts & Credit Cards
    // 3a. Explicit "A/c: 123456789012"
    currentText = currentText.replaceAllMapped(_explicitAccountNoRegex, (m) {
      final fullMatch = m.group(0)!;
      final accountDigits = m.group(1)!;
      final token = assignToken('ACCOUNT_', accountCounter, accountDigits);
      if (token == '[ACCOUNT_$accountCounter]') accountCounter++;
      return fullMatch.replaceFirst(accountDigits, token);
    });

    // 3b. Masked accounts "A/c **3948"
    currentText = currentText.replaceAllMapped(_maskedAccountRegex, (m) {
      final fullMatch = m.group(0)!;
      final maskedDigits = m.group(1)!;
      final token = assignToken('ACCOUNT_', accountCounter, maskedDigits);
      if (token == '[ACCOUNT_$accountCounter]') accountCounter++;
      return fullMatch.replaceFirst(maskedDigits, token);
    });

    // 3c. Standalone masked account tokens like "**3948" or "XX1234"
    currentText = currentText.replaceAllMapped(_standaloneMaskedCardRegex, (m) {
      final raw = m.group(0)!;
      final token = assignToken('ACCOUNT_', accountCounter, raw);
      if (token == '[ACCOUNT_$accountCounter]') accountCounter++;
      return token;
    });

    // 3d. 16-digit credit cards
    currentText = currentText.replaceAllMapped(_creditCardRegex, (m) {
      final raw = m.group(0)!;
      final token = assignToken('ACCOUNT_', accountCounter, raw);
      if (token == '[ACCOUNT_$accountCounter]') accountCounter++;
      return token;
    });

    // Step 4: Mask Identity Documents (Passport, PAN, Aadhaar)
    // 4a. Passport
    currentText = currentText.replaceAllMapped(_passportRegex, (m) {
      final raw = m.group(0)!;
      final token = assignToken('ID_DOC_', idCounter, raw);
      if (token == '[ID_DOC_$idCounter]') idCounter++;
      return token;
    });

    // 4b. PAN Card
    currentText = currentText.replaceAllMapped(_panRegex, (m) {
      final raw = m.group(0)!;
      final token = assignToken('ID_DOC_', idCounter, raw);
      if (token == '[ID_DOC_$idCounter]') idCounter++;
      return token;
    });

    // 4c. Aadhaar Number
    currentText = currentText.replaceAllMapped(_aadhaarRegex, (m) {
      final raw = m.group(0)!;
      final token = assignToken('ID_DOC_', idCounter, raw);
      if (token == '[ID_DOC_$idCounter]') idCounter++;
      return token;
    });

    // Step 5: Mask Phone numbers
    // 5a. International with +
    currentText = currentText.replaceAllMapped(_internationalPhoneRegex, (m) {
      final raw = m.group(0)!;
      final token = assignToken('PHONE_', phoneCounter, raw);
      if (token == '[PHONE_$phoneCounter]') phoneCounter++;
      return token;
    });

    // 5b. Indian mobile numbers
    currentText = currentText.replaceAllMapped(_indianPhoneRegex, (m) {
      final raw = m.group(0)!;
      final token = assignToken('PHONE_', phoneCounter, raw);
      if (token == '[PHONE_$phoneCounter]') phoneCounter++;
      return token;
    });

    return MaskedPayload(
      maskedText: currentText,
      tokenMap: tokenMap,
      totalTokensMasked: tokenMap.length,
    );
  }

  /// Unmasks all tokens in [responseText] using the local [tokenMap].
  ///
  /// Restores original personal identifiers locally on-device with 100% fidelity.
  String unmask(String responseText, Map<String, String> tokenMap) {
    if (tokenMap.isEmpty || responseText.isEmpty) {
      return responseText;
    }

    String restored = responseText;

    for (final entry in tokenMap.entries) {
      final token = entry.key; // e.g. '[PHONE_1]'
      final original = entry.value;

      // Direct replacement
      restored = restored.replaceAll(token, original);

      // Also tolerate LLM minor spacing quirks like '[ PHONE_1 ]'
      final stripped = token.replaceAll('[', '').replaceAll(']', '');
      final loosePattern = RegExp(r'\[\s*' + RegExp.escape(stripped) + r'\s*\]');
      restored = restored.replaceAll(loosePattern, original);
    }

    return restored;
  }
}
