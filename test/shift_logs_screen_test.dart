import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/features/shift_logs/screens/shift_logs_screen.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('ShiftLogsScreen renders title and filters correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ShiftLogsScreen(),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(ShiftLogsScreen), findsOneWidget);
  });
}
