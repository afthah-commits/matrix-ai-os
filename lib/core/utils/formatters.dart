import 'package:intl/intl.dart';

/// Formatting and conversion helpers for dates and storage sizes.
class Formatters {
  Formatters._();

  static final DateFormat _isoDayFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _readableDateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final DateFormat _shortTimeFormat = DateFormat('HH:mm');

  /// Formats [DateTime] to 'yyyy-MM-dd' for daily summary aggregation.
  static String formatIsoDay(DateTime dateTime) {
    return _isoDayFormat.format(dateTime);
  }

  /// Formats [DateTime] to 'yyyy-MM-dd HH:mm:ss'.
  static String formatReadableDateTime(DateTime dateTime) {
    return _readableDateTimeFormat.format(dateTime);
  }

  /// Formats [DateTime] to 'HH:mm'.
  static String formatShortTime(DateTime dateTime) {
    return _shortTimeFormat.format(dateTime);
  }

  /// Formats byte sizes into human-readable strings (B, KB, MB, GB).
  static String formatBytes(int bytes, [int decimals = 2]) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }
}
