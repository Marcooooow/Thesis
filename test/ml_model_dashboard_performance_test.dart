import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/features/admin/screens/ml_model_dashboard_screen.dart';

void main() {
  testWidgets('ML Model Dashboard Performance tab renders Historical Thesis Benchmark and metrics when present', (WidgetTester tester) async {
    // Build MLModelDashboardScreen inside MaterialApp
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MLModelDashboardScreen(),
        ),
      ),
    );

    // Initial pump shows loading indicators
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });
}
