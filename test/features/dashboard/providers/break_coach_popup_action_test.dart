library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/dashboard/models/break_coach_models.dart';
import 'package:intellibreak/features/dashboard/providers/break_coach_state.dart';
import 'package:intellibreak/features/dashboard/widgets/break_coach_notification.dart';
import 'package:provider/provider.dart';

void main() {
  group('Popup action regression', () {
    testWidgets('exceeded break recommendation hides Take Break button', (WidgetTester tester) async {
      final recommendation = BreakCoachRecommendation(
        recommendationId: 'r-exceeded',
        type: BreakCoachRecommendationType.shortBreak,
        title: 'Break duration exceeded',
        reason: 'Exceeded',
        suggestedBreakType: 'BREAK_1',
        generatedAt: DateTime.now(),
        trigger: BreakCoachTrigger.breakDurationExceeded,
      );

      final breakCoachState = BreakCoachState()..setBreakInProgressFromActiveBreak();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: breakCoachState),
            ChangeNotifierProvider(create: (_) => ThemeController()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: BreakCoachNotification(
                recommendation: recommendation,
                onTakeBreak: () {},
                onTakeLunch: () {},
                onSnooze: () {},
                onIgnore: () {},
                onContinue: () {},
                onClose: () {},
                visible: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Take Break'), findsNothing);
      expect(find.text('Dismiss reminder'), findsOneWidget);
    });

    testWidgets('exceeded lunch recommendation hides Take Lunch button', (WidgetTester tester) async {
      final recommendation = BreakCoachRecommendation(
        recommendationId: 'r-lunch-exceeded',
        type: BreakCoachRecommendationType.lunch,
        title: 'Lunch duration exceeded',
        reason: 'Exceeded',
        suggestedBreakType: 'LUNCH',
        generatedAt: DateTime.now(),
        trigger: BreakCoachTrigger.lunchDurationExceeded,
      );

      final breakCoachState = BreakCoachState()..setBreakInProgressFromActiveBreak();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: breakCoachState),
            ChangeNotifierProvider(create: (_) => ThemeController()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: BreakCoachNotification(
                recommendation: recommendation,
                onTakeBreak: () {},
                onTakeLunch: () {},
                onSnooze: () {},
                onIgnore: () {},
                onContinue: () {},
                onClose: () {},
                visible: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Take Lunch'), findsNothing);
      expect(find.text('Dismiss reminder'), findsOneWidget);
    });
  });
}
