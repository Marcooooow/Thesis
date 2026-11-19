import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/features/dashboard/screens/manager_dashboard_screen.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/providers/team_provider.dart';

void main() {
  testWidgets('ManagerDashboardContent renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => TeamProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ManagerDashboardContent(),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(ManagerDashboardContent), findsOneWidget);
  });
}
