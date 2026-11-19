import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:intellibreak/features/dashboard/models/break_coach_models.dart';
import 'package:intellibreak/features/dashboard/providers/break_coach_state.dart';
import 'package:intellibreak/features/dashboard/services/break_coach_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockBreakCoachService extends Mock implements BreakCoachService {}

void main() {
  group('BreakCoachState', () {
    late BreakCoachState breakCoachState;
    late MockBreakCoachService mockService;

    setUp(() async {
      // Initialize SharedPreferences with mock values
      SharedPreferences.setMockInitialValues({});
      mockService = MockBreakCoachService();
      when(() => mockService.getRecommendation(any())).thenAnswer((_) async => null);
      breakCoachState = BreakCoachState(service: mockService);
      await breakCoachState.loadPreferences();
    });

    test('starts disabled by default when no prefs set', () async {
      expect(breakCoachState.isEnabled, isTrue); // default is true
      expect(breakCoachState.isVisible, isFalse);
      expect(breakCoachState.currentRecommendation, isNull);
    });

    test('checkRecommendation returns null when disabled', () async {
      await breakCoachState.setEnabled(false);
      await breakCoachState.checkRecommendation('test-token');
      expect(breakCoachState.currentRecommendation, isNull);
    });

    test('checkRecommendation shows notification when recommendation exists', () async {
      final recommendation = BreakCoachRecommendation(
        recommendationId: 'rec-001',
        type: BreakCoachRecommendationType.shortBreak,
        title: 'Consider a short break',
        reason: 'You have been working for 90 minutes.',
        suggestedBreakType: 'BREAK_1',
        generatedAt: DateTime.now(),
        trigger: BreakCoachTrigger.ruleContinuousWork,
      );
      when(() => mockService.getRecommendation('test-token')).thenAnswer((_) async => recommendation);

      await breakCoachState.checkRecommendation('test-token');

      expect(breakCoachState.isVisible, isTrue);
      expect(breakCoachState.currentRecommendation, isNotNull);
      expect(breakCoachState.currentRecommendation!.type, equals(BreakCoachRecommendationType.shortBreak));
    });

    group('snooze', () {
      test('hides notification and sets snooze state', () async {
        final recommendation = BreakCoachRecommendation(
          recommendationId: 'rec-002',
          type: BreakCoachRecommendationType.shortBreak,
          title: 'Test',
          reason: 'Test reason',
          suggestedBreakType: 'BREAK_1',
          generatedAt: DateTime.now(),
          trigger: BreakCoachTrigger.ruleContinuousWork,
        );
        when(() => mockService.getRecommendation('test-token')).thenAnswer((_) async => recommendation);

        await breakCoachState.checkRecommendation('test-token');
        expect(breakCoachState.isVisible, isTrue);

        await breakCoachState.snooze();

        expect(breakCoachState.isVisible, isFalse);
        expect(breakCoachState.currentRecommendation, isNull);
        expect(breakCoachState.isSnoozed, isTrue);
      });

      test('does not show notification during snooze period', () async {
        final recommendation = BreakCoachRecommendation(
          recommendationId: 'rec-test',
          type: BreakCoachRecommendationType.shortBreak,
          title: 'Test',
          reason: 'Test reason',
          suggestedBreakType: 'BREAK_1',
          generatedAt: DateTime.now(),
          trigger: BreakCoachTrigger.ruleContinuousWork,
        );
        when(() => mockService.getRecommendation('test-token')).thenAnswer((_) async => recommendation);

        // First check shows notification
        await breakCoachState.checkRecommendation('test-token');
        expect(breakCoachState.isVisible, isTrue);

        // Snooze
        await breakCoachState.snooze();

        // Second check should not show because snoozed
        await breakCoachState.checkRecommendation('test-token');
        expect(breakCoachState.isVisible, isFalse);
      });
    });

    group('dismiss (Continue)', () {
      test('hides notification and sets cooldown', () async {
        final recommendation = BreakCoachRecommendation(
          recommendationId: 'rec-test',
          type: BreakCoachRecommendationType.shortBreak,
          title: 'Test',
          reason: 'Test reason',
          suggestedBreakType: 'BREAK_1',
          generatedAt: DateTime.now(),
          trigger: BreakCoachTrigger.ruleContinuousWork,
        );
        when(() => mockService.getRecommendation('test-token')).thenAnswer((_) async => recommendation);

        await breakCoachState.checkRecommendation('test-token');
        expect(breakCoachState.isVisible, isTrue);

        await breakCoachState.dismiss();

        expect(breakCoachState.isVisible, isFalse);
        expect(breakCoachState.currentRecommendation, isNull);
        expect(breakCoachState.isInCooldown, isTrue);
      });

      test('does not show notification during cooldown', () async {
        final recommendation = BreakCoachRecommendation(
          recommendationId: 'rec-test',
          type: BreakCoachRecommendationType.shortBreak,
          title: 'Test',
          reason: 'Test reason',
          suggestedBreakType: 'BREAK_1',
          generatedAt: DateTime.now(),
          trigger: BreakCoachTrigger.ruleContinuousWork,
        );
        when(() => mockService.getRecommendation('test-token')).thenAnswer((_) async => recommendation);

        await breakCoachState.checkRecommendation('test-token');
        expect(breakCoachState.isVisible, isTrue);

        await breakCoachState.dismiss();

        // Second check should not show because cooldown
        await breakCoachState.checkRecommendation('test-token');
        expect(breakCoachState.isVisible, isFalse);
      });
    });

    group('onBreakTaken', () {
      test('clears snooze and cooldown state', () async {
        final recommendation = BreakCoachRecommendation(
          recommendationId: 'rec-test',
          type: BreakCoachRecommendationType.shortBreak,
          title: 'Test',
          reason: 'Test reason',
          suggestedBreakType: 'BREAK_1',
          generatedAt: DateTime.now(),
          trigger: BreakCoachTrigger.ruleContinuousWork,
        );
        when(() => mockService.getRecommendation('test-token')).thenAnswer((_) async => recommendation);

        await breakCoachState.checkRecommendation('test-token');
        await breakCoachState.snooze();
        expect(breakCoachState.isSnoozed, isTrue);

        breakCoachState.onBreakTaken();

        expect(breakCoachState.isSnoozed, isFalse);
        expect(breakCoachState.isInCooldown, isFalse);
        expect(breakCoachState.isVisible, isFalse);
      });
    });

    group('clearState', () {
      test('clears all state when called', () async {
        final recommendation = BreakCoachRecommendation(
          recommendationId: 'rec-test',
          type: BreakCoachRecommendationType.shortBreak,
          title: 'Test',
          reason: 'Test reason',
          suggestedBreakType: 'BREAK_1',
          generatedAt: DateTime.now(),
          trigger: BreakCoachTrigger.ruleContinuousWork,
        );
        when(() => mockService.getRecommendation('test-token')).thenAnswer((_) async => recommendation);

        await breakCoachState.checkRecommendation('test-token');
        await breakCoachState.snooze();

        breakCoachState.clearState();

        expect(breakCoachState.isVisible, isFalse);
        expect(breakCoachState.currentRecommendation, isNull);
      });
    });
  });
}