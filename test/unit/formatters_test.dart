import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/core/utils/formatters.dart';

void main() {
  group('Formatters Tests', () {
    test('formatBytes formats zero and small bytes correctly', () {
      expect(Formatters.formatBytes(0), equals('0 B'));
      expect(Formatters.formatBytes(512), equals('512.00 B'));
    });

    test('formatBytes formats KB, MB, GB accurately', () {
      expect(Formatters.formatBytes(1024), equals('1.00 KB'));
      expect(Formatters.formatBytes(1024 * 1024 * 15), equals('15.00 MB'));
      expect(Formatters.formatBytes(1024 * 1024 * 1024), equals('1.00 GB'));
    });

    test('formatIsoDay formats standard ISO day string yyyy-MM-dd', () {
      final date = DateTime(2026, 11, 22, 14, 30);
      expect(Formatters.formatIsoDay(date), equals('2026-11-22'));
    });
  });
}
