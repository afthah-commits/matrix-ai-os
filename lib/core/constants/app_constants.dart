/// Core application constants for Matrix AI OS.
class AppConstants {
  AppConstants._();

  static const String appName = 'Matrix AI OS';
  static const String appVersion = '2.0.1';

  // Security & Keystore
  static const String secureStorageKeyName = 'matrix_ai_master_encryption_key_v1';
  static const int encryptionKeyLengthBytes = 32; // 256-bit AES key

  // Database & Storage
  static const String objectBoxDirName = 'matrix_ai_objectbox';
  static const int retentionPeriodDays = 30; // Rolling retention threshold

  // Target constraints
  static const int targetApkSizeLimitMb = 30;
}

/// Standard categories for ingested or generated memory nodes.
class MemoryCategory {
  MemoryCategory._();

  static const String transaction = 'transaction';
  static const String screenTime = 'screen_time';
  static const String callLog = 'call_log';
  static const String ocrDoc = 'ocr_doc';
  static const String note = 'note';

  static const List<String> all = [
    transaction,
    screenTime,
    callLog,
    ocrDoc,
    note,
  ];

  /// Categories that are permanent and exempted from rolling pruning.
  static const Set<String> immuneFromPruning = {
    ocrDoc,
  };
}
