import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/models/document_classification.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/document_classifier.dart';

void main() {
  group('DocumentClassifier Tests', () {
    test('classifies Passport with MRZ and extracts ID number', () {
      const passportText = '''
PASSPORT
Republic of India
Type: P  Country Code: IND  Passport No: Z9482014
Given Names: RAHUL
Surname: SHARMA
Nationality: INDIAN
Date of Birth: 15/08/1995
P<INDSHARMA<<RAHUL<<<<<<<<<<<<<<<<<<<<<<<<<<
Z9482014<0IND9508154M3110248<<<<<<<<<<<<<<<4
''';

      final classification = DocumentClassifier.classify(passportText);

      expect(classification.type, equals(DocumentType.passportId));
      expect(classification.confidence, greaterThanOrEqualTo(0.8));
      expect(classification.entities.idNumber, equals('Z9482014'));
      expect(classification.entities.dates, isNotEmpty);
    });

    test('classifies Retail Tax Invoice and extracts merchant & total amount', () {
      const invoiceText = '''
BLUE TOKAI COFFEE ROASTERS
TAX INVOICE
Invoice No: INV-2026-8492
Bill To: Walk-in Customer
Date: 22-Nov-2026
Item 1: Cold Brew Coffee x 2 - 450.00
Item 2: Sourdough Croissant - 250.00
Subtotal: 700.00
GST (18%): 126.00
Grand Total: ₹826.00
Thank you for your visit!
''';

      final classification = DocumentClassifier.classify(invoiceText);

      expect(classification.type, equals(DocumentType.invoiceReceipt));
      expect(classification.confidence, greaterThanOrEqualTo(0.7));
      expect(classification.entities.amount, equals(826.00));
      expect(classification.entities.idNumber, equals('INV-2026-8492'));
    });

    test('classifies Bank Statement and extracts account reference', () {
      const statementText = '''
AXIS BANK LIMITED
ACCOUNT STATEMENT / SUMMARY
Statement Period: 01-Oct-2026 to 31-Oct-2026
Account No: XX8943
Customer: Rahul Sharma
IFSC: UTIB0001234
Opening Balance: 15,400.00
Closing Balance: 32,850.50
Transaction History Summary: Total CR: 25,000.00 | Total DR: 7,549.50
''';

      final classification = DocumentClassifier.classify(statementText);

      expect(classification.type, equals(DocumentType.bankStatement));
      expect(classification.confidence, greaterThanOrEqualTo(0.7));
      expect(classification.entities.idNumber, equals('XX8943'));
    });

    test('classifies Airline Boarding Pass and extracts PNR', () {
      const ticketText = '''
INDIGO AIRLINES
BOARDING PASS / E-TICKET
Flight: 6E-204
PNR: YR7K9P
Departure: BLR 08:30  Gate: 12
Arrival: DEL 11:15    Seat: 14F
Date: 22/11/2026
''';

      final classification = DocumentClassifier.classify(ticketText);

      expect(classification.type, equals(DocumentType.ticketBooking));
      expect(classification.confidence, greaterThanOrEqualTo(0.7));
      expect(classification.entities.idNumber, equals('YR7K9P'));
    });

    test('classifies trivial or short text as general note', () {
      const noise = 'Just a small test note';
      final classification = DocumentClassifier.classify(noise);

      expect(classification.type, equals(DocumentType.generalNote));
    });
  });
}
