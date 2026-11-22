import 'package:objectbox/objectbox.dart';

/// Aggregated daily summary preserving temporal patterns and statistics
/// after raw logs older than 30 days are pruned.
@Entity()
class DailySummary {
  @Id()
  int id;

  /// ISO-8601 day format ('yyyy-MM-dd'). Unique to guarantee one summary per day.
  @Index()
  @Unique()
  String date;

  /// High-level text summary of the day's events, decisions, and context.
  String summaryText;

  /// Aggregated screen time in minutes for this day.
  int totalScreenTimeMinutes;

  /// Aggregated financial spend for this day.
  double totalSpent;

  /// Timestamp when this daily summary was computed or last updated.
  @Index()
  @Property(type: PropertyType.date)
  DateTime createdAt;

  DailySummary({
    this.id = 0,
    required this.date,
    required this.summaryText,
    this.totalScreenTimeMinutes = 0,
    this.totalSpent = 0.0,
    required this.createdAt,
  });
}
