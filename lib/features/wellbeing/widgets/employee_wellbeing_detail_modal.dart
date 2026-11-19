import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/wellbeing_models.dart';
import 'risk_tier_badge.dart';
import '../providers/wellbeing_provider.dart';

class EmployeeWellbeingDetailModal extends StatelessWidget {
  final String employeeId;

  const EmployeeWellbeingDetailModal({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<WellbeingProvider>(context);
    final detail = provider.selectedEmployeeDetail;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (provider.isLoadingDetail) {
      return Container(
        height: 400,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    if (detail == null) {
      return Container(
        height: 300,
        alignment: Alignment.center,
        child: const Text('No details available.'),
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
        maxWidth: 700,
      ),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E212B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.employeeName,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Week: ${detail.weekStart.toIso8601String().split('T')[0]} to ${detail.weekEnd.toIso8601String().split('T')[0]}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
                RiskTierBadge(riskTier: detail.riskTier),
              ],
            ),
            const Divider(height: 32),

            // Weekly Aggregates KPI Row
            const Text('Weekly Aggregates', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildKpiCard(context, 'Avg Worked / Day', '${detail.weeklyAggregates.avgWorkedHours}h'),
                _buildKpiCard(context, 'Break Compliance', '${detail.weeklyAggregates.avgBreakCompliancePct}%'),
                _buildKpiCard(context, 'Focus Rate', '${detail.weeklyAggregates.avgFocusRatePct}%'),
                _buildKpiCard(context, 'Check-ins', '${detail.weeklyAggregates.totalCheckins}'),
              ],
            ),
            const SizedBox(height: 24),

            // Detected Patterns
            const Text('Detected Patterns', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (detail.detectedPatterns.isEmpty)
              const Text('No behavioral patterns detected for this week.', style: TextStyle(color: Colors.grey))
            else
              ...detail.detectedPatterns.map((p) => Card(
                elevation: 0,
                color: isDark ? Colors.black12 : Colors.grey.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: p.evidenceStrength == 'high' ? Colors.red : Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(p.measurement, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text(p.evidenceStrength.toUpperCase(), style: const TextStyle(fontSize: 10)),
                        backgroundColor: p.evidenceStrength == 'high' ? Colors.red.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                      ),
                    ],
                  ),
                ),
              )),
            const SizedBox(height: 24),

            // Evidence Items
            const Text('Evidence & Risk Factors', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (detail.evidenceItems.isEmpty)
              const Text('No acute risk evidence triggered.', style: TextStyle(color: Colors.grey))
            else
              ...detail.evidenceItems.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record, size: 10, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.description, style: const TextStyle(fontSize: 14))),
                  ],
                ),
              )),
            const SizedBox(height: 24),

            // Recommended Actions for Manager
            const Text('Recommended Management Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...detail.recommendedActions.map((action) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(child: Text(action, style: const TextStyle(fontSize: 14))),
                ],
              ),
            )),
            const SizedBox(height: 24),

            // Privacy Notice Footer
            Center(
              child: Text(
                '🔒 Privacy Protected: Aggregated trends only. Raw check-in notes & stress factors are private to employee.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(BuildContext context, String title, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
