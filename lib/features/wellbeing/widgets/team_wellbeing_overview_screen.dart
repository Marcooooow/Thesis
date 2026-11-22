import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wellbeing_provider.dart';
import '../models/wellbeing_models.dart';

class TeamWellbeingOverviewScreen extends StatefulWidget {
  const TeamWellbeingOverviewScreen({super.key});

  @override
  State<TeamWellbeingOverviewScreen> createState() => _TeamWellbeingOverviewScreenState();
}

class _TeamWellbeingOverviewScreenState extends State<TeamWellbeingOverviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      Provider.of<WellbeingProvider>(context, listen: false).setSelectedWeek(monday.subtract(const Duration(days: 7)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<WellbeingProvider>(context);
    final overview = provider.overview;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Team Well-being Insights',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Grouped weekly work-pattern and recovery trends',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => provider.fetchWeeklyOverview(),
                tooltip: 'Refresh Overview',
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (provider.isLoading && overview == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (provider.error != null)
            Expanded(
              child: Center(
                child: Text('Error: ${provider.error}', style: const TextStyle(color: Colors.red)),
              ),
            )
          else if (overview == null)
            const Expanded(child: Center(child: Text('No data available.')))
          else if (overview.teamSummary.privacySuppressed || overview.teamSummary.totalEmployees < 5)
            Expanded(child: _buildPrivacyNotice(!overview.teamSummary.privacySuppressed && overview.teamSummary.totalEmployees == 0))
          else ...[
            _buildRecoverySummary(overview.employees),
            const SizedBox(height: 16),
            // Summary Cards / Tier breakdown
            _buildSummaryRow(overview.employees),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Team figures are grouped and anonymised. They are advisory and not a diagnosis. Individual wellbeing tiers and check-in answers are private.',
                  style: TextStyle(color: isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecoverySummary(List<EmployeeRiskSummary> employees) {
    final atRisk = employees.where((e) => e.riskTier == RiskTier.high || e.riskTier == RiskTier.critical).toList();
    final breakCount = atRisk.length;
    final leaveCount = employees.where((e) => e.riskTier == RiskTier.critical && e.topEvidence.any((item) => item.toLowerCase().contains('recurring overwork'))).length;
    final unknownCount = employees.where((e) => e.riskTier == RiskTier.insufficientData).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Recovery Support Summary', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('$breakCount employees may need a recovery break · $leaveCount may benefit from discussing time off'),
          if (unknownCount > 0) ...[
            const SizedBox(height: 4),
            Text('$unknownCount employees have insufficient data for an assessment.', style: const TextStyle(color: Colors.grey)),
          ],
          const SizedBox(height: 4),
          const Text('These are advisory counts for the selected week. Leave remains the employee’s choice and follows normal approval.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
    );
  }

  Widget _buildPrivacyNotice(bool noTeam) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.privacy_tip_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      noTeam
                          ? 'No team data is available for this selection.'
                          : 'Not enough people to show this safely. Group insights are available when at least 5 people are included.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildSummaryRow(List<EmployeeRiskSummary> employees) {
    final byTier = <String, int>{
      'critical': employees.where((e) => e.riskTier == RiskTier.critical).length,
      'high': employees.where((e) => e.riskTier == RiskTier.high).length,
      'moderate': employees.where((e) => e.riskTier == RiskTier.moderate).length,
      'low': employees.where((e) => e.riskTier == RiskTier.low).length,
      'insufficient_data': employees.where((e) => e.riskTier == RiskTier.insufficientData).length,
    };
    final metrics = <(String, String, Color)>[
      ('Total Monitored', '${employees.length}', Colors.blue),
      ('Critical', '${byTier['critical']}', RiskTier.critical.color),
      ('High Risk', '${byTier['high']}', RiskTier.high.color),
      ('Moderate', '${byTier['moderate']}', RiskTier.moderate.color),
      ('Low Risk', '${byTier['low']}', RiskTier.low.color),
      ('Insufficient Data', '${byTier['insufficient_data']}', RiskTier.insufficientData.color),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 650 ? 2 : 3;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final metric in metrics)
              SizedBox(width: width, child: _buildMetricBox(metric.$1, metric.$2, metric.$3)),
          ],
        );
      },
    );
  }

  Widget _buildMetricBox(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

}
