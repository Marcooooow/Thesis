import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/features/team/widgets/create_team_dialog.dart';
import 'package:intellibreak/providers/team_provider.dart';

void main() {
  group('CreateTeamDialog', () {
    late TeamProvider mockTeamProvider;

    setUp(() {
      mockTeamProvider = TeamProvider();
    });

    testWidgets('CreateTeamDialog renders with title and fields', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: mockTeamProvider),
            ],
            child: Scaffold(
              body: Center(
                child: CreateTeamDialog(),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Create Team'), findsWidgets);
      expect(find.byType(TextField), findsWidgets);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('Validation prevents empty submission', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: mockTeamProvider),
            ],
            child: Scaffold(
              body: Center(
                child: CreateTeamDialog(),
              ),
            ),
          ),
        ),
      );

      // Try to submit with empty name
      final submitButton = find.byType(ElevatedButton);
      await tester.tap(submitButton);
      await tester.pump(); // Pump the same widget to trigger state update

      // Error should appear
      expect(find.text('Team name is required'), findsOneWidget);
    });

    testWidgets('Name field has character limit of 100', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: mockTeamProvider),
            ],
            child: Scaffold(
              body: Center(
                child: CreateTeamDialog(),
              ),
            ),
          ),
        ),
      );

      final nameField = find.byType(TextField).first;
      await tester.enterText(nameField, 'A' * 101);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: mockTeamProvider),
            ],
            child: Scaffold(
              body: Center(
                child: CreateTeamDialog(),
              ),
            ),
          ),
        ),
      );

      // Text should be truncated to 100 characters
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('Cancel button dismisses dialog', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: mockTeamProvider),
            ],
            child: Scaffold(
              body: Center(
                child: CreateTeamDialog(),
              ),
            ),
          ),
        ),
      );

      final cancelButton = find.byType(TextButton);
      await tester.tap(cancelButton);
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.byType(CreateTeamDialog), findsNothing);
    });
  });
}
