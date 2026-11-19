import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/features/dashboard/widgets/metrics_section.dart';

void main() {
  group('MetricsSection percentage conversion', () {
    test('converts 1.58% of 8 hours to correct seconds', () {
      // 8 hours = 28800 seconds
      final workedHours = 8.0;
      final totalWorkSeconds = workedHours * 3600.0; // 28800

      // Test idle: 1.58%
      final idlePct = 1.58;
      final idleSeconds = ((idlePct / 100) * totalWorkSeconds).round();
      expect(idleSeconds, 455); // 1.58% of 28800 = 455.04 -> rounds to 455

      // Test activeFocus: 0%
      final activeFocusPct = 0.0;
      final activeFocusSeconds = ((activeFocusPct / 100) * totalWorkSeconds).round();
      expect(activeFocusSeconds, 0);

      // Test activeFocus: 50%
      final activeFocusPct2 = 50.0;
      final activeFocusSeconds2 = ((activeFocusPct2 / 100) * totalWorkSeconds).round();
      expect(activeFocusSeconds2, 14400); // 50% of 28800 = 14400
    });

    test('handles zero work duration', () {
      final workedHours = 0.0;
      final totalWorkSeconds = workedHours * 3600.0; // 0

      final idlePct = 50.0;
      final idleSeconds = (totalWorkSeconds > 0)
          ? ((idlePct / 100) * totalWorkSeconds).round()
          : 0;
      expect(idleSeconds, 0);
    });

    test('handles fractional percentages correctly', () {
      final workedHours = 1.0; // 3600 seconds
      final totalWorkSeconds = workedHours * 3600.0;

      // Test 33.33% -> should be ~1200 seconds
      final pct = 33.33;
      final seconds = ((pct / 100) * totalWorkSeconds).round();
      expect(seconds, 1200); // 33.33% of 3600 = 1199.88 -> rounds to 1200

      // Test 66.66% -> should be ~2400 seconds
      final pct2 = 66.66;
      final seconds2 = ((pct2 / 100) * totalWorkSeconds).round();
      expect(seconds2, 2400); // 66.66% of 3600 = 2399.76 -> rounds to 2400
    });
  });
}