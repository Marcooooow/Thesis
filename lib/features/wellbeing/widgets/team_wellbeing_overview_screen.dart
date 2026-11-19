import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wellbeing_provider.dart';
import '../models/wellbeing_models.dart';
import 'risk_tier_badge.dart';
import 'employee_wellbeing_detail_modal.dart';

class TeamWellbeingOverviewScreen extends StatefulWidget {
  const TeamWellbeingOverviewScreen({super.key});

  @override
  State<TeamWellbeingOverviewScreen> createState() => _TeamWellbeingOverviewScreenState();
}

class _TeamWellbeingOverviewScreenState extends State<TeamWellbeingOverviewScreen> {
  String _searchQuery = '';
  RiskTier? _tierFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      Provider.of<WellbeingProvider>(context, listen: false).setSelectedWeek(monday.subtract(const Duration(days: 7)));
    });
  }

  void _showDetailModal(BuildContext context, String employeeId) {
    final provider = Provider.of<WellbeingProvider>(context, listen: false);
    provider.fetchEmployeeDetail(employeeId);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: EmployeeWellbeingDetailModal(employeeId: employeeId),
      ),
    );
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
                    'Weekly Employee Well-being Monitoring',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Rule-based weekly risk overview & behavioral pattern analysis',
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
          else ...[
            _buildRecoverySummary(overview.employees),
            const SizedBox(height: 16),
            // Summary Cards / Tier breakdown
            _buildSummaryRow(overview.employees),
            const SizedBox(height: 24),

            // Search and Filter Bar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search employee by name...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<RiskTier?>(
                  value: _tierFilter,
                  hint: const Text('Filter by Tier'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Tiers')),
                    ...RiskTier.values.map((tier) => DropdownMenuItem(
                      value: tier,
                      child: Text(tier.label),
                    )),
                  ],
                  onChanged: (val) => setState(() => _tierFilter = val),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Employee Grid / Table
            Expanded(
              child: _buildEmployeeList(overview.employees, isDark),
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
          if (atRisk.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('View at-risk employees (${atRisk.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
              children: atRisk.map((employee) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${employee.employeeName} · ${employee.riskTier.label}'),
                subtitle: Text(employee.topEvidence.join('; ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showDetailModal(context, employee.employeeId),
              )).toList(),
            ),
        ]),
      ),
    );
  }

  Widget _buildSummaryRow(List<EmployeeRiskSummary> employees) {
    final byTier = <String, int>{
      'critical': employees.where((e) => e.riskTier == RiskTier.critical).length,
      'high': employees.where((e) => e.riskTier == RiskTier.high).length,
      'moderate': employees.where((e) => e.riskTier == RiskTier.moderate).length,
      'low': employees.where((e) => e.riskTier == RiskTier.low).length,
      'insufficient_data': employees.where((e) => e.riskTier == RiskTier.insufficientData).length,
    };
    return Row(
      children: [
        _buildMetricBox('Total Monitored', '${employees.length}', Colors.blue),
        const SizedBox(width: 12),
        _buildMetricBox('Critical', '${byTier["critical"]}', RiskTier.critical.color),
        const SizedBox(width: 12),
        _buildMetricBox('High Risk', '${byTier["high"]}', RiskTier.high.color),
        const SizedBox(width: 12),
        _buildMetricBox('Moderate', '${byTier["moderate"]}', RiskTier.moderate.color),
        const SizedBox(width: 12),
        _buildMetricBox('Low Risk', '${byTier["low"]}', RiskTier.low.color),
        const SizedBox(width: 12),
        _buildMetricBox('Insufficient Data', '${byTier["insufficient_data"]}', RiskTier.insufficientData.color),
      ],
    );
  }

  Widget _buildMetricBox(String title, String value, Color color) {
    return Expanded(
      child: Container(
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
      ),
    );
  }

  Widget _buildEmployeeList(List<EmployeeRiskSummary> employees, bool isDark) {
    final filtered = employees.where((e) {
      final matchesSearch = e.employeeName.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesTier = _tierFilter == null || e.riskTier == _tierFilter;
      return matchesSearch && matchesTier;
    }).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('No employees match the current filters.'));
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final emp = filtered[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            title: Row(
              children: [
                Text(emp.employeeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(width: 12),
                RiskTierBadge(riskTier: emp.riskTier, compact: true),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                'Primary Concern: ${emp.primaryConcern}',
                style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade700, fontSize: 13),
              ),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showDetailModal(context, emp.employeeId),
          ),
        );
      },
    );
  }
}
