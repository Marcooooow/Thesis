import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/widgets/state_display.dart';
import 'package:intellibreak/core/design_system.dart';

void main() {
  group('QoL Audit Coverage - StateDisplay & Component States', () {
    testWidgets('1. Employee Dashboard / StateDisplay handles loading state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StateDisplay(
              isLoading: true,
              isEmpty: false,
              loadingMessage: 'Loading employee dashboard...',
              content: const Text('Dashboard Content'),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading employee dashboard...'), findsOneWidget);
      expect(find.text('Dashboard Content'), findsNothing);
    });

    testWidgets('2. Shift Controller / StateDisplay handles success content state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StateDisplay(
              isLoading: false,
              isEmpty: false,
              content: const Text('Active Shift: 08:00 - 17:00'),
            ),
          ),
        ),
      );

      expect(find.text('Active Shift: 08:00 - 17:00'), findsOneWidget);
    });

    testWidgets('3. Attendance and Scheduling / StateDisplay handles empty state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StateDisplay(
              isLoading: false,
              isEmpty: true,
              emptyMessage: 'No attendance records found for this period.',
              emptyIcon: Icons.calendar_today,
              content: const Text('Attendance Content'),
            ),
          ),
        ),
      );

      expect(find.text('No attendance records found for this period.'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
      expect(find.text('Attendance Content'), findsNothing);
    });

    testWidgets('4. Wellbeing Check-ins / StateDisplay handles error state and sanitization', (WidgetTester tester) async {
      bool retryCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StateDisplay(
              isLoading: false,
              isEmpty: false,
              errorMessage: 'SocketException: Failed host lookup (http://localhost:8000)',
              onRetry: () => retryCalled = true,
              content: const Text('Wellbeing Content'),
            ),
          ),
        ),
      );

      // Verify sanitized error message
      expect(find.text('Connection error. Please check your network and try again.'), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retryCalled, isTrue);
    });

    testWidgets('5. Recommendations and Feedback / StateDisplay preserves existing data on refresh error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StateDisplay(
              isLoading: false,
              isEmpty: false,
              errorMessage: '500 Internal Server Error',
              hasExistingData: true,
              content: const Text('Previous Recommendations List'),
            ),
          ),
        ),
      );

      // Existing data preserved, error banner shown
      expect(find.text('Previous Recommendations List'), findsOneWidget);
      expect(find.textContaining('Failed to refresh: Server error'), findsOneWidget);
    });

    testWidgets('6. Manager Dashboard / Empty state with custom action', (WidgetTester tester) async {
      bool actionClicked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StateDisplay(
              isLoading: false,
              isEmpty: true,
              emptyMessage: 'No team members assigned.',
              emptyAction: ElevatedButton(
                onPressed: () => actionClicked = true,
                child: const Text('Add Team Member'),
              ),
              content: const Text('Manager Content'),
            ),
          ),
        ),
      );

      expect(find.text('No team members assigned.'), findsOneWidget);
      expect(find.text('Add Team Member'), findsOneWidget);

      await tester.tap(find.text('Add Team Member'));
      expect(actionClicked, isTrue);
    });

    testWidgets('7. Admin Dashboard / Server error sanitization', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StateDisplay(
              isLoading: false,
              isEmpty: false,
              errorMessage: 'sqlalchemy.exc.OperationalError: (psycopg2.OperationalError) database connection failed',
              content: const Text('Admin Analytics Content'),
            ),
          ),
        ),
      );

      expect(find.text('Server error. Our team has been notified. Please try again later.'), findsOneWidget);
    });

    testWidgets('8. Manage Accounts / Unauthorized access sanitization', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StateDisplay(
              isLoading: false,
              isEmpty: false,
              errorMessage: '403 Forbidden: Unauthorized access to accounts',
              content: const Text('Accounts List'),
            ),
          ),
        ),
      );

      expect(find.text('Session expired or unauthorized access. Please sign in again.'), findsOneWidget);
    });
  });
}
