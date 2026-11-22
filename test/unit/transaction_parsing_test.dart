import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/features/device_ingestion/domain/models/transaction_notification_model.dart';

void main() {
  group('Transaction Notification Parsing Tests', () {
    test('parses Axis Bank debit alert correctly', () {
      const text =
          'Axis Bank: Your A/c no. XX3948 is debited for INR 1,499.00 on 22-Nov-26 towards SWIGGY. Available Bal: INR 24,500.50.';
      final parsed = TransactionNotification.parseText(
        text: text,
        title: 'Axis Bank Alert',
        appPackage: 'com.axis.mobile',
      );

      expect(parsed.amount, equals(1499.00));
      expect(parsed.txType, equals('debit'));
      expect(parsed.accountRef, contains('3948'));
      expect(parsed.merchant.toLowerCase(), contains('swiggy'));
    });

    test('parses HDFC Bank UPI debit correctly', () {
      const text =
          'HDFC Bank: Rs 450.00 debited from A/c **1029 to VPA swiggy@icici on 22-11-26.';
      final parsed = TransactionNotification.parseText(
        text: text,
        title: 'HDFC Bank',
        appPackage: 'com.snapwork.hdfc',
      );

      expect(parsed.amount, equals(450.00));
      expect(parsed.txType, equals('debit'));
      expect(parsed.accountRef, contains('1029'));
      expect(parsed.merchant, contains('swiggy@icici'));
    });

    test('parses SBI credit alert correctly', () {
      const text =
          'SBI: Dear Customer, A/c *8492 has been credited by Rs. 25,000.00 on 22Nov26 by transfer from SALARY.';
      final parsed = TransactionNotification.parseText(
        text: text,
        title: 'SBI Alert',
        appPackage: 'com.sbi.lotusintouch',
      );

      expect(parsed.amount, equals(25000.00));
      expect(parsed.txType, equals('credit'));
      expect(parsed.accountRef, contains('8492'));
    });

    test('parses Google Pay UPI payment correctly', () {
      const text = 'Paid ₹320.00 to Chai Point using Google Pay UPI.';
      final parsed = TransactionNotification.parseText(
        text: text,
        title: 'Google Pay',
        appPackage: 'com.google.android.apps.nbu.paisa.user',
      );

      expect(parsed.amount, equals(320.00));
      expect(parsed.txType, equals('debit'));
      expect(parsed.merchant.toLowerCase(), contains('chai point'));
    });

    test('parses CRED card payment correctly', () {
      const text = 'CRED: ₹5,000.00 paid towards Axis Bank Credit Card ending in 4102.';
      final parsed = TransactionNotification.parseText(
        text: text,
        title: 'CRED',
        appPackage: 'com.dreamplug.androidapp',
      );

      expect(parsed.amount, equals(5000.00));
      expect(parsed.txType, equals('debit'));
      expect(parsed.accountRef, contains('4102'));
    });

    test('ignores or marks unknown for regular non-financial notifications', () {
      const text = 'Hey, are you free for the sync today at 4 PM?';
      final parsed = TransactionNotification.parseText(
        text: text,
        title: 'WhatsApp: Rahul',
        appPackage: 'com.whatsapp',
      );

      expect(parsed.amount, equals(0.0));
      expect(parsed.txType, equals('unknown'));
    });
  });
}
