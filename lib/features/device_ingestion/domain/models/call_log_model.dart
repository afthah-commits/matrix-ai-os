/// Represents an ingested telephony call log item.
class CallLogEntry {
  final String number;
  final String contactName;
  final String type; // INCOMING, OUTGOING, MISSED, REJECTED
  final DateTime timestamp;
  final int durationSeconds;

  const CallLogEntry({
    required this.number,
    required this.contactName,
    required this.type,
    required this.timestamp,
    required this.durationSeconds,
  });

  factory CallLogEntry.fromMap(Map<dynamic, dynamic> map) {
    final rawDate = (map['timestamp'] as num?)?.toInt() ?? 0;
    return CallLogEntry(
      number: map['number'] as String? ?? '',
      contactName: map['contactName'] as String? ?? '',
      type: map['type'] as String? ?? 'UNKNOWN',
      timestamp: DateTime.fromMillisecondsSinceEpoch(rawDate),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'number': number,
      'contactName': contactName,
      'type': type,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'durationSeconds': durationSeconds,
    };
  }

  /// Formatted duration string, e.g. "2m 15s" or "45s".
  String get formattedDuration {
    if (durationSeconds <= 0) return '0s';
    final mins = durationSeconds ~/ 60;
    final secs = durationSeconds % 60;
    if (mins > 0) {
      return '${mins}m ${secs}s';
    }
    return '${secs}s';
  }
}
