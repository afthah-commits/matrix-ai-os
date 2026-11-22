/// Document classifications for on-device OCR vision indexing.
enum DocumentType {
  passportId('PASSPORT_ID'),
  invoiceReceipt('INVOICE_RECEIPT'),
  bankStatement('BANK_STATEMENT'),
  ticketBooking('TICKET_BOOKING'),
  generalNote('GENERAL_NOTE');

  final String displayName;
  const DocumentType(this.displayName);

  static DocumentType fromString(String val) {
    switch (val.toUpperCase()) {
      case 'PASSPORT_ID':
        return DocumentType.passportId;
      case 'INVOICE_RECEIPT':
        return DocumentType.invoiceReceipt;
      case 'BANK_STATEMENT':
        return DocumentType.bankStatement;
      case 'TICKET_BOOKING':
        return DocumentType.ticketBooking;
      default:
        return DocumentType.generalNote;
    }
  }
}

/// Extracted entities found inside an indexed document.
class ExtractedEntities {
  final String? idNumber;
  final double? amount;
  final List<String> dates;
  final String? merchantOrIssuer;

  const ExtractedEntities({
    this.idNumber,
    this.amount,
    this.dates = const [],
    this.merchantOrIssuer,
  });

  Map<String, dynamic> toMap() {
    return {
      'idNumber': idNumber,
      'amount': amount,
      'dates': dates,
      'merchantOrIssuer': merchantOrIssuer,
    };
  }

  factory ExtractedEntities.fromMap(Map<String, dynamic> map) {
    return ExtractedEntities(
      idNumber: map['idNumber'] as String?,
      amount: (map['amount'] as num?)?.toDouble(),
      dates: (map['dates'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      merchantOrIssuer: map['merchantOrIssuer'] as String?,
    );
  }
}

/// Result of document classification.
class DocumentClassification {
  final DocumentType type;
  final double confidence;
  final ExtractedEntities entities;
  final String summary;

  const DocumentClassification({
    required this.type,
    required this.confidence,
    required this.entities,
    required this.summary,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.displayName,
      'confidence': confidence,
      'entities': entities.toMap(),
      'summary': summary,
    };
  }

  factory DocumentClassification.fromMap(Map<String, dynamic> map) {
    return DocumentClassification(
      type: DocumentType.fromString(map['type'] as String? ?? ''),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      entities: map['entities'] is Map
          ? ExtractedEntities.fromMap(Map<String, dynamic>.from(map['entities']))
          : const ExtractedEntities(),
      summary: map['summary'] as String? ?? '',
    );
  }
}
