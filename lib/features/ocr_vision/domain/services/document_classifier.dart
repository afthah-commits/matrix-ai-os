import 'package:matrix_ai_os/features/ocr_vision/domain/models/document_classification.dart';

/// Pure Dart rule-based and regex document classifier for extracted OCR text.
class DocumentClassifier {
  DocumentClassifier._();

  /// Classifies extracted OCR text into a structured [DocumentClassification].
  static DocumentClassification classify(String text) {
    final trimmed = text.trim();
    if (trimmed.length < 15) {
      return const DocumentClassification(
        type: DocumentType.generalNote,
        confidence: 0.1,
        entities: ExtractedEntities(),
        summary: 'Empty or trivial text',
      );
    }

    final lower = trimmed.toLowerCase();

    // 1. Check Passport / Government ID
    final isPassport = _checkPassport(lower, trimmed);
    if (isPassport.matched) {
      final idNum = _extractPassportNumber(trimmed);
      final dates = _extractDates(trimmed);
      return DocumentClassification(
        type: DocumentType.passportId,
        confidence: isPassport.confidence,
        entities: ExtractedEntities(
          idNumber: idNum,
          dates: dates,
          merchantOrIssuer: 'Government Authority',
        ),
        summary: 'Passport / Official ID document (ID: ${idNum ?? "Indexed"})',
      );
    }

    // 2. Check Invoice / Receipt
    final isInvoice = _checkInvoice(lower);
    if (isInvoice.matched) {
      final amount = _extractInvoiceAmount(trimmed);
      final merchant = _extractMerchant(trimmed);
      final dates = _extractDates(trimmed);
      final idNum = _extractInvoiceNumber(trimmed);

      final amtStr = amount != null ? ' - \$${amount.toStringAsFixed(2)}' : '';
      return DocumentClassification(
        type: DocumentType.invoiceReceipt,
        confidence: isInvoice.confidence,
        entities: ExtractedEntities(
          idNumber: idNum,
          amount: amount,
          dates: dates,
          merchantOrIssuer: merchant,
        ),
        summary: 'Invoice / Receipt from ${merchant ?? "Vendor"}$amtStr',
      );
    }

    // 3. Check Bank Statement
    final isBankStatement = _checkBankStatement(lower);
    if (isBankStatement.matched) {
      final dates = _extractDates(trimmed);
      final accNo = _extractAccountNumber(trimmed);
      return DocumentClassification(
        type: DocumentType.bankStatement,
        confidence: isBankStatement.confidence,
        entities: ExtractedEntities(
          idNumber: accNo,
          dates: dates,
          merchantOrIssuer: 'Bank / Financial Institution',
        ),
        summary: 'Bank Statement / Account Summary ${accNo != null ? "(A/c $accNo)" : ""}',
      );
    }

    // 4. Check Ticket / Booking
    final isTicket = _checkTicket(lower);
    if (isTicket.matched) {
      final pnr = _extractPnr(trimmed);
      final dates = _extractDates(trimmed);
      return DocumentClassification(
        type: DocumentType.ticketBooking,
        confidence: isTicket.confidence,
        entities: ExtractedEntities(
          idNumber: pnr,
          dates: dates,
          merchantOrIssuer: 'Travel / Transport Operator',
        ),
        summary: 'Travel Ticket / Booking Pass ${pnr != null ? "(PNR: $pnr)" : ""}',
      );
    }

    // 5. Fallback: General Note
    final dates = _extractDates(trimmed);
    return DocumentClassification(
      type: DocumentType.generalNote,
      confidence: 0.5,
      entities: ExtractedEntities(dates: dates),
      summary: 'General Document / Notes (${trimmed.split('\n').first})',
    );
  }

  static ({bool matched, double confidence}) _checkPassport(String lower, String raw) {
    int score = 0;
    if (lower.contains('passport')) score += 3;
    if (lower.contains('republic of') || lower.contains('government of')) score += 2;
    if (lower.contains('nationality')) score += 2;
    if (lower.contains('date of birth') || lower.contains('dob')) score += 2;
    if (lower.contains('surname') || lower.contains('given names')) score += 2;
    if (raw.contains('P<') || raw.contains('p<')) score += 4; // MRZ line indicator

    if (score >= 5) {
      return (matched: true, confidence: (score / 10).clamp(0.6, 0.98));
    }
    return (matched: false, confidence: 0.0);
  }

  static ({bool matched, double confidence}) _checkInvoice(String lower) {
    int score = 0;
    if (lower.contains('tax invoice') || lower.contains('invoice')) score += 3;
    if (lower.contains('receipt') || lower.contains('bill to')) score += 2;
    if (lower.contains('subtotal') || lower.contains('total amount')) score += 2;
    if (lower.contains('gstin') || lower.contains('vat') || lower.contains('tax')) score += 2;
    if (lower.contains('order id') || lower.contains('invoice no')) score += 2;

    if (score >= 4) {
      return (matched: true, confidence: (score / 10).clamp(0.6, 0.95));
    }
    return (matched: false, confidence: 0.0);
  }

  static ({bool matched, double confidence}) _checkBankStatement(String lower) {
    int score = 0;
    if (lower.contains('bank statement') || lower.contains('account statement')) score += 4;
    if (lower.contains('closing balance') || lower.contains('opening balance')) score += 3;
    if (lower.contains('transaction history') || lower.contains('statement period')) score += 2;
    if (lower.contains('ifsc') || lower.contains('cr/dr')) score += 2;

    if (score >= 4) {
      return (matched: true, confidence: (score / 10).clamp(0.6, 0.95));
    }
    return (matched: false, confidence: 0.0);
  }

  static ({bool matched, double confidence}) _checkTicket(String lower) {
    int score = 0;
    if (lower.contains('boarding pass') || lower.contains('e-ticket')) score += 4;
    if (lower.contains('flight') || lower.contains('train') || lower.contains('railway')) score += 2;
    if (lower.contains('pnr') || lower.contains('booking reference')) score += 3;
    if (lower.contains('seat') && (lower.contains('gate') || lower.contains('coach'))) score += 3;
    if (lower.contains('departure') && lower.contains('arrival')) score += 2;

    if (score >= 4) {
      return (matched: true, confidence: (score / 10).clamp(0.6, 0.95));
    }
    return (matched: false, confidence: 0.0);
  }

  static String? _extractPassportNumber(String raw) {
    // 1. Explicit labeled pattern: "Passport No: Z9482014" or "Passport Number: Z9482014"
    final labeledMatch = RegExp(
      r'passport\s*(?:no\.?|number|#)\s*[:.]?\s*([A-Z0-9]{7,9})',
      caseSensitive: false,
    ).firstMatch(raw);
    if (labeledMatch != null) {
      return labeledMatch.group(1);
    }

    // 2. Standalone passport number: 1 letter followed by 7 or 8 digits
    final match = RegExp(r'\b[A-Z][0-9]{7,8}\b', caseSensitive: false).firstMatch(raw);
    if (match != null) {
      return match.group(0);
    }

    // 3. Fallback: MRZ line pattern (e.g. Z9482014<0IND...)
    final mrzMatch = RegExp(r'\b([A-Z0-9]{7,9})<[0-9]', caseSensitive: false).firstMatch(raw);
    return mrzMatch?.group(1);
  }

  static double? _extractInvoiceAmount(String raw) {
    // Priority 1: Grand Total / Net Payable / Total Amount
    final grandMatch = RegExp(
      r'(?:grand\s+total|net\s+payable|total\s+amount)[\s:]*(?:rs\.?|inr|₹|\$)?\s*([0-9,]+(?:\.[0-9]{2})?)',
      caseSensitive: false,
    ).firstMatch(raw);

    if (grandMatch != null) {
      final clean = grandMatch.group(1)?.replaceAll(',', '');
      return double.tryParse(clean ?? '');
    }

    // Priority 2: Explicit "Total: $X.XX"
    final totalMatch = RegExp(
      r'(?:^|\n)\s*total[\s:]*(?:rs\.?|inr|₹|\$)?\s*([0-9,]+(?:\.[0-9]{2})?)',
      caseSensitive: false,
    ).firstMatch(raw);

    if (totalMatch != null) {
      final clean = totalMatch.group(1)?.replaceAll(',', '');
      return double.tryParse(clean ?? '');
    }

    // Priority 3: Subtotal / Generic Amount
    final fallbackMatch = RegExp(
      r'(?:subtotal|amount)[\s:]*(?:rs\.?|inr|₹|\$)?\s*([0-9,]+(?:\.[0-9]{2})?)',
      caseSensitive: false,
    ).firstMatch(raw);

    if (fallbackMatch != null) {
      final clean = fallbackMatch.group(1)?.replaceAll(',', '');
      return double.tryParse(clean ?? '');
    }
    return null;
  }

  static String? _extractMerchant(String raw) {
    final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.length > 2).toList();
    if (lines.isNotEmpty) {
      // First prominent line is usually the store/company header
      final header = lines.first;
      if (header.length <= 40 && !header.toLowerCase().contains('invoice')) {
        return header;
      }
    }
    return null;
  }

  static String? _extractInvoiceNumber(String raw) {
    final match = RegExp(r'(?:invoice|bill|order)\s*(?:no\.?|id|#)[\s:]*([A-Za-z0-9_-]+)', caseSensitive: false).firstMatch(raw);
    return match?.group(1);
  }

  static String? _extractAccountNumber(String raw) {
    final match = RegExp(r'(?:a/c|account)\s*(?:no\.?|number)?[\s:]*([xX*]*[0-9]{3,6})', caseSensitive: false).firstMatch(raw);
    return match?.group(1);
  }

  static String? _extractPnr(String raw) {
    final match = RegExp(r'\b(?:pnr|booking\s*(?:ref|id|#))[\s:]*([A-Z0-9]{6,10})\b', caseSensitive: false).firstMatch(raw);
    return match?.group(1);
  }

  static List<String> _extractDates(String raw) {
    // Matches: 22-Nov-2026, 22/11/2026, 2026-11-22, 22-11-26
    final matches = RegExp(r'\b(?:\d{1,2}[-/.](?:[A-Za-z]{3}|\d{1,2})[-/.]\d{2,4}|\d{4}-\d{2}-\d{2})\b').allMatches(raw);
    return matches.map((m) => m.group(0)!).toSet().take(3).toList();
  }
}
