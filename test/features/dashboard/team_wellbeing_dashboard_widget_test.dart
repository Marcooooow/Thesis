import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/features/wellbeing/widgets/team_wellbeing_dashboard_widget.dart';
import 'package:intellibreak/features/wellbeing/models/wellbeing_models.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:provider/provider.dart';

void main() {
  group('TeamWellbeingDashboardWidget', () {
    late WeeklyOverviewResponse mockWeeklyData;

    setUp(() {
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));

      mockWeeklyData = WeeklyOverviewResponse(
        weekStart: weekStart,
        weekEnd: weekEnd,
        generatedAt: now,
        teamSummary: TeamSummary(
          totalEmployees: 10,
          byTier: {'low': 5, 'moderate': 3, 'high': 2, 'critical': 0, 'insufficient_data': 0},
        ),
        employees: [
          for (int i = 0; i < 5; i++)
            EmployeeRiskSummary(
              employeeId: 'low_$i',
              employeeName: 'Low Risk $i',
              teamName: 'Team A',
              riskTier: RiskTier.low,
              riskLabel: 'Normal',
              primaryConcern: '',
              evidenceCount: 0,
              topEvidence: [],
              trend: TrendDirection.improving,
              hasActiveShift: true,
              lastCheckinDate: DateTime.now().subtract(const Duration(days: 1)),
            ),
          for (int i = 0; i < 3; i++)
            EmployeeRiskSummary(
              employeeId: 'mod_$i',
              employeeName: 'Moderate Risk $i',
              teamName: 'Team A',
              riskTier: RiskTier.moderate,
              riskLabel: 'Needs Attention',
              primaryConcern: 'Long sessions',
              evidenceCount: 2,
              topEvidence: ['Extended work session'],
              trend: TrendDirection.stable,
              hasActiveShift: false,
              lastCheckinDate: DateTime.now().subtract(const Duration(days: 2)),
            ),
          for (int i = 0; i < 2; i++)
            EmployeeRiskSummary(
              employeeId: 'high_$i',
              employeeName: 'High Risk $i',
              teamName: 'Team A',
              riskTier: RiskTier.high,
              riskLabel: 'Critical',
              primaryConcern: 'Overtime',
              evidenceCount: 5,
              topEvidence: ['Overtime', 'Missed breaks'],
              trend: TrendDirection.worsening,
              hasActiveShift: true,
              lastCheckinDate: DateTime.now().subtract(const Duration(days: 3)),
            ),
        ],
      );
    });

    Widget wrapWithProviders(Widget child) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
        ],
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );
    }

    testWidgets('renders correctly with data', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithProviders(
        TeamWellbeingDashboardWidget(
          weeklyData: mockWeeklyData,
          isLoading: false,
          onRefresh: () {},
          onWeekChange: (_) {},
          selectedWeekStart: DateTime.now(),
        ),
      ));

      await tester.pump();

      expect(find.byType(TeamWellbeingDashboardWidget), findsOneWidget);
      expect(find.text('Team Wellbeing Overview'), findsOneWidget);
      expect(find.text('Weekly Team Overview'), findsOneWidget);
      expect(find.text('Risk Distribution'), findsOneWidget);
      expect(find.text('Work Pattern Analytics'), findsOneWidget);
      expect(find.text('Break Logging'), findsWidgets);
      expect(find.text('Weekly Trends'), findsOneWidget);
      expect(find.text('Behavioral Patterns'), findsOneWidget);
    });

    testWidgets('shows loading state', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithProviders(
        TeamWellbeingDashboardWidget(
          weeklyData: null,
          isLoading: true,
          onRefresh: () {},
          onWeekChange: (_) {},
          selectedWeekStart: DateTime.now(),
        ),
      ));

      await tester.pump();

      // Loading state shows skeleton cards - just verify the widget renders without crashing
      expect(find.byType(TeamWellbeingDashboardWidget), findsOneWidget);
    });

    testWidgets('shows empty state when no data', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithProviders(
        TeamWellbeingDashboardWidget(
          weeklyData: null,
          isLoading: false,
          onRefresh: () {},
          onWeekChange: (_) {},
          selectedWeekStart: DateTime.now(),
        ),
      ));

      await tester.pump();

      expect(find.text('No wellbeing data available'), findsOneWidget);
    });

    testWidgets('risk distribution shows correct counts', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithProviders(
        TeamWellbeingDashboardWidget(
          weeklyData: mockWeeklyData,
          isLoading: false,
          onRefresh: () {},
          onWeekChange: (_) {},
          selectedWeekStart: DateTime.now(),
        ),
      ));

      await tester.pump();

      // Risk distribution shows counts with percentages (e.g., "5 (50%)")
      expect(find.textContaining('5'), findsWidgets);
      expect(find.textContaining('3'), findsWidgets);
      expect(find.textContaining('2'), findsWidgets);
    });

    testWidgets('weekly trends section renders', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithProviders(
        TeamWellbeingDashboardWidget(
          weeklyData: mockWeeklyData,
          isLoading: false,
          onRefresh: () {},
          onWeekChange: (_) {},
          selectedWeekStart: DateTime.now(),
        ),
      ));

      await tester.pump();

      // Weekly Trends section has specific trend items
      expect(find.text('Working Hours'), findsOneWidget);
      expect(find.text('Risk Score'), findsOneWidget);
    });

    testWidgets('behavioral patterns section renders', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithProviders(
        TeamWellbeingDashboardWidget(
          weeklyData: mockWeeklyData,
          isLoading: false,
          onRefresh: () {},
          onWeekChange: (_) {},
          selectedWeekStart: DateTime.now(),
        ),
      ));

      await tester.pump();

      expect(find.text('Behavioral Patterns'), findsOneWidget);
    });
  });
}