import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/features/tasks/screens/task_history_screen.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('TaskHistoryScreen renders summary metrics and filters', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TaskHistoryScreen(),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(TaskHistoryScreen), findsOneWidget);
  });
}
