import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:intellibreak/features/dashboard/services/break_coach_service.dart';
import 'package:intellibreak/features/dashboard/services/work_service.dart';
import 'package:intellibreak/features/dashboard/models/break_coach_models.dart';

class MockWorkService extends Mock implements WorkService {}

void main() {
  group('BreakCoachService', () {
    late BreakCoachService breakCoachService;
    late MockWorkService mockWorkService;

    setUp(() {
      mockWorkService = MockWorkService();
      breakCoachService = BreakCoachService(workService: mockWorkService);
    });

    tearDown(() {
      // Clean up after each test
    });

    group('getRecommendation', () {
      test('returns null when no active session', () async {
        when(() => mockWorkService.getActiveSession(any())).thenAnswer((_) async => null);

        final recommendation = await breakCoachService.getRecommendation('test-token');

        expect(recommendation, isNull);
      });
    });

    group('checkContinuousWorkRule', () {
      test('returns high priority recommendation at 120+ minutes', () async {
        final recommendation = await breakCoachService.checkContinuousWorkRule(
          125,
          125,
        );

        expect(recommendation, isNotNull);
        expect(recommendation!.type, equals(BreakCoachRecommendationType.shortBreak));
        expect(recommendation.trigger, equals(BreakCoachTrigger.ruleContinuousWorkHighPriority));
        expect(recommendation.title, equals('Time for a break?'));
        expect(recommendation.suggestedBreakType, equals('BREAK_1'));
      });

      test('returns normal priority recommendation at 90+ minutes', () async {
        final recommendation = await breakCoachService.checkContinuousWorkRule(
          95,
          95,
        );

        expect(recommendation, isNotNull);
        expect(recommendation!.type, equals(BreakCoachRecommendationType.shortBreak));
        expect(recommendation.trigger, equals(BreakCoachTrigger.ruleContinuousWork));
        expect(recommendation.title, equals('Consider a short break'));
      });

      test('returns null below 90 minutes', () async {
        final recommendation = await breakCoachService.checkContinuousWorkRule(
          85,
          85,
        );

        expect(recommendation, isNull);
      });

      test('returns null when time since last break is less than threshold', () async {
        final recommendation = await breakCoachService.checkContinuousWorkRule(
          125,
          30,
        );

        expect(recommendation, isNull);
      });
    });

    group('checkLunchRule', () {
      test('returns lunch recommendation at 180+ minutes without lunch', () async {
        final recommendation = await breakCoachService.checkLunchRule(
          185,
          false,
        );

        expect(recommendation, isNotNull);
        expect(recommendation!.type, equals(BreakCoachRecommendationType.lunch));
        expect(recommendation.trigger, equals(BreakCoachTrigger.ruleLunchTime));
        expect(recommendation.title, equals('Lunch break time?'));
        expect(recommendation.suggestedBreakType, equals('LUNCH'));
      });

      test('returns null if lunch already taken', () async {
        final recommendation = await breakCoachService.checkLunchRule(
          185,
          true,
        );

        expect(recommendation, isNull);
      });

      test('returns null below 180 minutes', () async {
        final recommendation = await breakCoachService.checkLunchRule(
          175,
          false,
        );

        expect(recommendation, isNull);
      });
    });

    group('getSessionDurationMinutes', () {
      test('returns correct duration for valid session start time', () async {
        final now = DateTime.now();
        final startedAt = now.subtract(const Duration(minutes: 90));
        when(() => mockWorkService.getActiveSession(any())).thenAnswer((_) async => {
          'started_at': startedAt.toIso8601String(),
        });

        final duration = await breakCoachService.getSessionDurationMinutes('test-token');
        expect(duration, equals(90));
      });

      test('returns 0 when session start time is null', () async {
        when(() => mockWorkService.getActiveSession(any())).thenAnswer((_) async => {
          'started_at': null,
        });

        final duration = await breakCoachService.getSessionDurationMinutes('test-token');
        expect(duration, equals(0));
      });
    });

    group('getTimeSinceLastBreak', () {
      test('returns correct time since last break', () async {
        final now = DateTime.now();
        final endedAt = now.subtract(const Duration(minutes: 30));
        when(() => mockWorkService.getActiveSession(any())).thenAnswer((_) async => {
          'id': 'session-123',
          'started_at': DateTime.now().subtract(const Duration(minutes: 120)).toIso8601String(),
        });
        when(() => mockWorkService.getActiveSessionBreaks(any())).thenAnswer((_) async => [
          {
            'started_at': endedAt.subtract(const Duration(minutes: 60)).toIso8601String(),
            'ended_at': endedAt.toIso8601String(),
          }
        ]);

        final timeSinceBreak = await breakCoachService.getTimeSinceLastBreak('test-token');
        expect(timeSinceBreak, equals(30));
      });

      test('returns session duration when no breaks', () async {
        when(() => mockWorkService.getActiveSessionBreaks(any())).thenAnswer((_) async => []);
        when(() => mockWorkService.getActiveSession(any())).thenAnswer((_) async => {
          'started_at': DateTime.now().subtract(const Duration(minutes: 60)).toIso8601String(),
        });

        final timeSinceBreak = await breakCoachService.getTimeSinceLastBreak('test-token');
        expect(timeSinceBreak, equals(60));
      });
    });

    group('shouldGenerateRecommendation', () {
      test('returns true for qualifying continuous-work duration', () async {
        when(() => mockWorkService.getActiveSession(any())).thenAnswer((_) async => {
          'id': 'session-123',
          'started_at': DateTime.now().subtract(const Duration(minutes: 95)).toIso8601String(),
        });
        when(() => mockWorkService.getActiveSessionBreaks(any())).thenAnswer((_) async => []);

        final result = await breakCoachService.shouldGenerateRecommendation('test-token');
        expect(result, isTrue);
      });

      test('returns false below threshold', () async {
        when(() => mockWorkService.getActiveSession(any())).thenAnswer((_) async => {
          'id': 'session-123',
          'started_at': DateTime.now().subtract(const Duration(minutes: 85)).toIso8601String(),
        });
        when(() => mockWorkService.getActiveSessionBreaks(any())).thenAnswer((_) async => []);

        final result = await breakCoachService.shouldGenerateRecommendation('test-token');
        expect(result, isFalse);
      });
    });
  });
}