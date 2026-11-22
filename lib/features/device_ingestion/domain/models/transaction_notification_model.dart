/// Structured representation of a banking or payment transaction alert.
class TransactionNotification {
  final double amount;
  final String merchant;
  final String txType; // "debit", "credit", or "unknown"
  final String accountRef;
  final DateTime timestamp;
  final String appPackage;
  final String rawText;

  const TransactionNotification({
    required this.amount,
    required this.merchant,
    required this.txType,
    required this.accountRef,
    required this.timestamp,
    required this.appPackage,
    required this.rawText,
  });

  factory TransactionNotification.fromMap(Map<dynamic, dynamic> map) {
    final rawDate = (map['timestamp'] as num?)?.toInt() ?? 0;
    return TransactionNotification(
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      merchant: map['merchant'] as String? ?? 'Unknown Merchant',
      txType: map['txType'] as String? ?? 'unknown',
      accountRef: map['accountRef'] as String? ?? '',
      timestamp: rawDate > 0
          ? DateTime.fromMillisecondsSinceEpoch(rawDate)
          : DateTime.now(),
      appPackage: map['packageName'] as String? ?? '',
      rawText: map['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'merchant': merchant,
      'txType': txType,
      'accountRef': accountRef,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'appPackage': appPackage,
      'rawText': rawText,
    };
  }

  /// Parses raw transaction text into structured [TransactionNotification].
  /// Supports Axis Bank, HDFC, SBI, ICICI, UPI (Google Pay, PhonePe, Paytm, CRED).
  static TransactionNotification parseText({
    required String text,
    String title = '',
    String appPackage = '',
    DateTime? timestamp,
  }) {
    final lower = text.toLowerCase();
    final combined = title.isNotEmpty ? '$title: $text' : text;

    // 1. Transaction Type
    String type = 'unknown';
    if (lower.contains('debited') ||
        lower.contains('spent') ||
        lower.contains('paid') ||
        lower.contains('sent')) {
      type = 'debit';
    } else if (lower.contains('credited') ||
        lower.contains('received') ||
        lower.contains('refund')) {
      type = 'credit';
    }

    // 2. Extract Amount
    // Matches: Rs. 1,450.50 | INR 250 | ₹500.00 | $45.00 | 1200.00 debited
    double amount = 0.0;
    final amountRegex = RegExp(
      r'(?:(?:rs\.?|inr|₹|\$)\s*([0-9,]+(?:\.[0-9]{1,2})?))|(?:([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:debited|credited|spent|paid))',
      caseSensitive: false,
    );
    final match = amountRegex.firstMatch(combined);
    if (match != null) {
      final rawStr = match.group(1) ?? match.group(2);
      if (rawStr != null) {
        amount = double.tryParse(rawStr.replaceAll(',', '').trim()) ?? 0.0;
      }
    }

    // 3. Extract Merchant / Vendor / Counterparty
    // Matches: "to VPA abc@okhdfcbank", "at Amazon", "to Swiggy", "towards Uber"
    String merchant = title.isNotEmpty ? title : 'Unknown Merchant';
    final merchantRegex = RegExp(
      r'(?:to\s+(?:vpa\s+)?|at\s+|info\s*:\s*|towards\s+)([a-zA-Z0-9_.-@]+(?:\s+[a-zA-Z0-9_.-]+)?)',
      caseSensitive: false,
    );
    final mMatch = merchantRegex.firstMatch(combined);
    if (mMatch != null) {
      final found = mMatch.group(1)?.trim();
      if (found != null && found.isNotEmpty && !found.toLowerCase().startsWith('a/c')) {
        merchant = found;
      }
    }

    // 4. Extract Account Reference (e.g. A/c **1234 or XX4321)
    String accountRef = '';
    final accRegex = RegExp(
      r'(?:a/c|account|ac|card)\s*(?:no\.?)?\s*(?:ending(?:\s+in)?)?\s*([xX*]*[0-9]{3,4})',
      caseSensitive: false,
    );
    final aMatch = accRegex.firstMatch(combined);
    if (aMatch != null) {
      accountRef = aMatch.group(1) ?? '';
    }

    return TransactionNotification(
      amount: amount,
      merchant: merchant,
      txType: type,
      accountRef: accountRef,
      timestamp: timestamp ?? DateTime.now(),
      appPackage: appPackage,
      rawText: text,
    );
  }
}
