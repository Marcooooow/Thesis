import 'package:flutter/material.dart';

enum RiskTier {
  insufficientData(0, 'Insufficient Data', Color(0xFF9E9E9E)),
  low(1, 'Low Risk', Color(0xFF4CAF50)),
  moderate(2, 'Moderate Risk', Color(0xFFFF9800)),
  high(3, 'High Risk', Color(0xFFF44336)),
  critical(4, 'Critical Risk', Color(0xFFB71C1C));

  final int value;
  final String label;
  final Color color;
  const RiskTier(this.value, this.label, this.color);

  static RiskTier fromValue(int val) {
    return RiskTier.values.firstWhere((e) => e.value == val, orElse: () => RiskTier.insufficientData);
  }
}

enum TrendDirection {
  improving('improving'),
  stable('stable'),
  worsening('worsening'),
  unknown('unknown');

  final String value;
  const TrendDirection(this.value);

  static TrendDirection fromValue(String val) {
    return TrendDirection.values.firstWhere(
      (e) => e.value == val.toLowerCase(),
      orElse: () => TrendDirection.unknown,
    );
  }

  static TrendDirection fromString(String val) {
    return TrendDirection.values.firstWhere(
      (e) => e.value == val.toLowerCase(),
      orElse: () => TrendDirection.unknown,
    );
  }
}

enum EvidenceType {
  workedHoursExcess('worked_hours_excess'),
  breakComplianceLow('break_compliance_low'),
  wellbeingDeclining('wellbeing_declining'),
  focusDeclining('focus_declining'),
  skippedBreaks('skipped_breaks'),
  unknown('unknown');

  final String value;
  const EvidenceType(this.value);

  static EvidenceType fromString(String val) {
    return EvidenceType.values.firstWhere(
      (e) => e.value == val,
      orElse: () => EvidenceType.unknown,
    );
  }
}

class EvidenceItem {
  final EvidenceType type;
  final String description;
  final double metricValue;
  final double threshold;
  final int daysAffected;

  EvidenceItem({
    required this.type,
    required this.description,
    required this.metricValue,
    required this.threshold,
    required this.daysAffected,
  });

  factory EvidenceItem.fromJson(Map<String, dynamic> json) {
    return EvidenceItem(
      type: EvidenceType.fromString(json['type'] ?? ''),
      description: json['description'] ?? '',
      metricValue: (json['metric_value'] as num?)?.toDouble() ?? 0.0,
      threshold: (json['threshold'] as num?)?.toDouble() ?? 0.0,
      daysAffected: json['days_affected'] as int? ?? 0,
    );
  }
}

class DataQuality {
  final int sessionsCount;
  final int checkinsCount;
  final String baselineSource;
  final bool partialWeek;
  final String? dataLimitation;

  DataQuality({
    required this.sessionsCount,
    required this.checkinsCount,
    required this.baselineSource,
    required this.partialWeek,
    this.dataLimitation,
  });

  // Computed getter: classification is possible when there's sufficient data
  // Backend considers classification possible when there's no data limitation
  bool get classificationPossible => dataLimitation == null;

  factory DataQuality.fromJson(Map<String, dynamic> json) {
    return DataQuality(
      sessionsCount: json['sessions_count'] as int? ?? 0,
      checkinsCount: json['checkins_count'] as int? ?? 0,
      baselineSource: json['baseline_source'] ?? '',
      partialWeek: json['partial_week'] as bool? ?? false,
      dataLimitation: json['data_limitation'],
    );
  }
}

class DetectedPattern {
  final String patternId;
  final String displayName;
  final String evidenceStrength;
  final String measurement;
  final String? dataLimitations;
  final int daysTriggered;

  DetectedPattern({
    required this.patternId,
    required this.displayName,
    required this.evidenceStrength,
    required this.measurement,
    this.dataLimitations,
    required this.daysTriggered,
  });

  factory DetectedPattern.fromJson(Map<String, dynamic> json) {
    return DetectedPattern(
      patternId: json['pattern_id'] ?? '',
      displayName: json['display_name'] ?? '',
      evidenceStrength: json['evidence_strength'] ?? 'low',
      measurement: json['measurement'] ?? '',
      dataLimitations: json['data_limitations'],
      daysTriggered: json['days_triggered'] as int? ?? 0,
    );
  }
}

class DailyBreakdown {
  final DateTime date;
  final double workedHours;
  final double targetHours;
  final int breakCompliancePct;
  final double focusRatePct;
  final int checkinCount;
  final double? avgStressLevel;
  final double? avgEnergyLevel;
  final List<String> patternsDetected;

  DailyBreakdown({
    required this.date,
    required this.workedHours,
    required this.targetHours,
    required this.breakCompliancePct,
    required this.focusRatePct,
    required this.checkinCount,
    this.avgStressLevel,
    this.avgEnergyLevel,
    required this.patternsDetected,
  });

  factory DailyBreakdown.fromJson(Map<String, dynamic> json) {
    return DailyBreakdown(
      date: DateTime.parse(json['date']),
      workedHours: (json['worked_hours'] as num?)?.toDouble() ?? 0.0,
      targetHours: (json['target_hours'] as num?)?.toDouble() ?? 0.0,
      breakCompliancePct: json['break_compliance_pct'] as int? ?? 0,
      focusRatePct: (json['focus_rate_pct'] as num?)?.toDouble() ?? 0.0,
      checkinCount: json['checkin_count'] as int? ?? 0,
      avgStressLevel: (json['avg_stress_level'] as num?)?.toDouble(),
      avgEnergyLevel: (json['avg_energy_level'] as num?)?.toDouble(),
      patternsDetected: List<String>.from(json['patterns_detected'] ?? []),
    );
  }
}

class WeeklyAggregates {
  final double avgWorkedHours;
  final int avgBreakCompliancePct;
  final double avgFocusRatePct;
  final int totalCheckins;
  final double? avgStressLevel;
  final double? avgEnergyLevel;
  final double? avgWorkloadManageability;
  final List<String> patternsDetected;
  final DataQuality? dataQuality;
  // Phase 2: Week-over-week comparison fields
  final double previousWeekAvgWorkedHours;
  final int previousWeekAvgBreakCompliancePct;
  final double previousWeekAvgFocusRatePct;
  final int previousWeekTotalCheckins;
  final TrendDirection? trendWorkedHours;
  final TrendDirection? trendBreakCompliance;
  final TrendDirection? trendFocusRate;
  final bool privacySuppressed;

  WeeklyAggregates({
    required this.avgWorkedHours,
    required this.avgBreakCompliancePct,
    required this.avgFocusRatePct,
    required this.totalCheckins,
    this.avgStressLevel,
    this.avgEnergyLevel,
    this.avgWorkloadManageability,
    this.patternsDetected = const [],
    this.dataQuality,
    this.previousWeekAvgWorkedHours = 0.0,
    this.previousWeekAvgBreakCompliancePct = 0,
    this.previousWeekAvgFocusRatePct = 0.0,
    this.previousWeekTotalCheckins = 0,
    this.trendWorkedHours,
    this.trendBreakCompliance,
    this.trendFocusRate,
    this.privacySuppressed = false,
  });

  factory WeeklyAggregates.fromJson(Map<String, dynamic> json) {
    return WeeklyAggregates(
      avgWorkedHours: (json['avg_worked_hours'] as num?)?.toDouble() ?? 0.0,
      avgBreakCompliancePct: json['avg_break_compliance_pct'] as int? ?? 0,
      avgFocusRatePct: (json['avg_focus_rate_pct'] as num?)?.toDouble() ?? 0.0,
      totalCheckins: json['total_checkins'] as int? ?? 0,
      avgStressLevel: (json['avg_stress_level'] as num?)?.toDouble(),
      avgEnergyLevel: (json['avg_energy_level'] as num?)?.toDouble(),
      avgWorkloadManageability: (json['avg_workload_manageability'] as num?)?.toDouble(),
      patternsDetected: List<String>.from(json['patterns_detected'] ?? []),
      dataQuality: json['data_quality'] != null ? DataQuality.fromJson(json['data_quality']) : null,
      previousWeekAvgWorkedHours: (json['previous_week_avg_worked_hours'] as num?)?.toDouble() ?? 0.0,
      previousWeekAvgBreakCompliancePct: json['previous_week_avg_break_compliance_pct'] as int? ?? 0,
      previousWeekAvgFocusRatePct: (json['previous_week_avg_focus_rate_pct'] as num?)?.toDouble() ?? 0.0,
      previousWeekTotalCheckins: json['previous_week_total_checkins'] as int? ?? 0,
      trendWorkedHours: json['trend_worked_hours'] != null ? TrendDirection.fromValue(json['trend_worked_hours']) : null,
      trendBreakCompliance: json['trend_break_compliance'] != null ? TrendDirection.fromValue(json['trend_break_compliance']) : null,
      trendFocusRate: json['trend_focus_rate'] != null ? TrendDirection.fromValue(json['trend_focus_rate']) : null,
      privacySuppressed: json['privacy_suppressed'] as bool? ?? false,
    );
  }
}

class EmployeeRiskSummary {
  final String employeeId;
  final String employeeName;
  final String teamName;
  final RiskTier riskTier;
  final String riskLabel;
  final String primaryConcern;
  final int evidenceCount;
  final List<String> topEvidence;
  final TrendDirection trend;
  final bool hasActiveShift;
  final DateTime? lastCheckinDate;

  EmployeeRiskSummary({
    required this.employeeId,
    required this.employeeName,
    required this.teamName,
    required this.riskTier,
    required this.riskLabel,
    required this.primaryConcern,
    required this.evidenceCount,
    required this.topEvidence,
    required this.trend,
    required this.hasActiveShift,
    this.lastCheckinDate,
  });

  factory EmployeeRiskSummary.fromJson(Map<String, dynamic> json) {
    return EmployeeRiskSummary(
      employeeId: json['employee_id'].toString(),
      employeeName: json['employee_name'] ?? 'Employee',
      teamName: json['team_name'] ?? 'Team',
      riskTier: RiskTier.fromValue(json['risk_tier'] as int? ?? 0),
      riskLabel: json['risk_label'] ?? 'Unknown',
      primaryConcern: json['primary_concern'] ?? '',
      evidenceCount: json['evidence_count'] as int? ?? 0,
      topEvidence: List<String>.from(json['top_evidence'] ?? []),
      trend: TrendDirection.fromString(json['trend'] ?? 'stable'),
      hasActiveShift: json['has_active_shift'] as bool? ?? false,
      lastCheckinDate: json['last_checkin_date'] != null ? DateTime.parse(json['last_checkin_date']) : null,
    );
  }
}

class TeamSummary {
  final int totalEmployees;
  final Map<String, int> byTier;
  final String name;
  final bool privacySuppressed;

  TeamSummary({
    required this.totalEmployees,
    required this.byTier,
    this.name = 'Team',
    this.privacySuppressed = false,
  });

  factory TeamSummary.fromJson(Map<String, dynamic> json) {
    final rawByTier = json['by_tier'] as Map<String, dynamic>? ?? {};
    return TeamSummary(
      totalEmployees: json['total_employees'] as int? ?? 0,
      byTier: rawByTier.map((k, v) => MapEntry(k, v as int)),
      name: json['name'] ?? 'Team',
      privacySuppressed: json['privacy_suppressed'] as bool? ?? false,
    );
  }
}

class WeeklyOverviewResponse {
  final DateTime weekStart;
  final DateTime weekEnd;
  final DateTime generatedAt;
  final TeamSummary teamSummary;
  final List<EmployeeRiskSummary> employees;

  WeeklyOverviewResponse({
    required this.weekStart,
    required this.weekEnd,
    required this.generatedAt,
    required this.teamSummary,
    required this.employees,
  });

  factory WeeklyOverviewResponse.fromJson(Map<String, dynamic> json) {
    return WeeklyOverviewResponse(
      weekStart: DateTime.parse(json['week_start']),
      weekEnd: DateTime.parse(json['week_end']),
      generatedAt: DateTime.parse(json['generated_at']),
      teamSummary: TeamSummary.fromJson(json['team_summary'] ?? {}),
      employees: (json['employees'] as List? ?? []).map((e) => EmployeeRiskSummary.fromJson(e)).toList(),
    );
  }
}

class EmployeeDetailResponse {
  final String employeeId;
  final String employeeName;
  final DateTime weekStart;
  final DateTime weekEnd;
  final RiskTier riskTier;
  final String riskLabel;
  final List<DailyBreakdown> dailyBreakdown;
  final WeeklyAggregates weeklyAggregates;
  final List<DetectedPattern> detectedPatterns;
  final List<EvidenceItem> evidenceItems;
  final List<String> recommendedActions;
  final DataQuality dataQuality;

  EmployeeDetailResponse({
    required this.employeeId,
    required this.employeeName,
    required this.weekStart,
    required this.weekEnd,
    required this.riskTier,
    required this.riskLabel,
    required this.dailyBreakdown,
    required this.weeklyAggregates,
    required this.detectedPatterns,
    required this.evidenceItems,
    required this.recommendedActions,
    required this.dataQuality,
  });

  factory EmployeeDetailResponse.fromJson(Map<String, dynamic> json) {
    return EmployeeDetailResponse(
      employeeId: json['employee_id'].toString(),
      employeeName: json['employee_name'] ?? 'Employee',
      weekStart: DateTime.parse(json['week_start']),
      weekEnd: DateTime.parse(json['week_end']),
      riskTier: RiskTier.fromValue(json['risk_tier'] as int? ?? 0),
      riskLabel: json['risk_label'] ?? 'Unknown',
      dailyBreakdown: (json['daily_breakdown'] as List? ?? []).map((e) => DailyBreakdown.fromJson(e)).toList(),
      weeklyAggregates: WeeklyAggregates.fromJson(json['weekly_aggregates'] ?? {}),
      detectedPatterns: (json['detected_patterns'] as List? ?? []).map((e) => DetectedPattern.fromJson(e)).toList(),
      evidenceItems: (json['evidence_items'] as List? ?? []).map((e) => EvidenceItem.fromJson(e)).toList(),
      recommendedActions: List<String>.from(json['recommended_actions'] ?? []),
      dataQuality: DataQuality.fromJson(json['data_quality'] ?? {}),
    );
  }
}
