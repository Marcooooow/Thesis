import 'package:flutter/material.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';

/// One of the five weekly work-life balance survey dimensions.
class WlbDimension {
  final String field; // backend field name
  final String label;
  final String prompt; // wording shown in the weekly check-in
  final IconData icon;

  const WlbDimension({
    required this.field,
    required this.label,
    required this.prompt,
    required this.icon,
  });
}

const List<WlbDimension> kWlbDimensions = [
  WlbDimension(
    field: 'rating_disconnect',
    label: 'Disconnecting',
    prompt: 'I was able to disconnect from work outside my scheduled hours.',
    icon: Icons.power_settings_new_rounded,
  ),
  WlbDimension(
    field: 'rating_personal_time',
    label: 'Personal time',
    prompt: 'I had enough time for personal and family responsibilities.',
    icon: Icons.favorite_border_rounded,
  ),
  WlbDimension(
    field: 'rating_responsibilities_balance',
    label: 'Balance',
    prompt: 'My work responsibilities were balanced with my personal life.',
    icon: Icons.balance_rounded,
  ),
  WlbDimension(
    field: 'rating_schedule_satisfaction',
    label: 'Schedule',
    prompt: 'I was satisfied with my working hours and schedule flexibility.',
    icon: Icons.event_available_outlined,
  ),
  WlbDimension(
    field: 'rating_recovery',
    label: 'Recovery',
    prompt: 'I felt sufficiently recovered after my working days.',
    icon: Icons.bedtime_outlined,
  ),
];

/// Score bands mirror WLBAnalysisService._calculate_wlb_label on the backend.
String wlbBandLabel(double? score) {
  if (score == null) return 'No data';
  if (score >= 80) return 'Excellent';
  if (score >= 70) return 'Good';
  if (score >= 50) return 'Fair';
  if (score >= 30) return 'Poor';
  return 'Critical';
}

/// Colour for a 0-100 score. Muted tones rather than saturated traffic lights.
Color wlbBandColor(double? score) {
  if (score == null) return const Color(0xFF8A94A6);
  if (score >= 70) return const Color(0xFF2F8F6B); // healthy
  if (score >= 50) return const Color(0xFFB7871F); // watch
  return const Color(0xFFC2573F); // needs attention
}

class WlbWeekPoint {
  final DateTime weekStart;
  final double? score;
  final double hours;
  const WlbWeekPoint({required this.weekStart, this.score, required this.hours});
}

class WlbSurveyEntry {
  final DateTime weekStart;
  final double score;
  final Map<String, int> ratings;
  const WlbSurveyEntry({
    required this.weekStart,
    required this.score,
    required this.ratings,
  });
}

class WlbRecommendation {
  final String title;
  final String description;
  final String? reason;
  final String? category;
  const WlbRecommendation({
    required this.title,
    required this.description,
    this.reason,
    this.category,
  });
}

class WlbOverview {
  /// Monday of the current reporting week.
  final DateTime currentWeekStart;
  final bool submittedThisWeek;
  final WlbSurveyEntry? latest;
  final List<WlbSurveyEntry> history; // newest first
  final List<WlbWeekPoint> weeks; // oldest first
  final String trend; // improving | stable | declining
  final double? scoreChange;
  final String? message;
  final String? riskLabel;
  final List<WlbRecommendation> recommendations;
  final Map<String, dynamic> indicators; // behavioural indicators

  const WlbOverview({
    required this.currentWeekStart,
    required this.submittedThisWeek,
    required this.latest,
    required this.history,
    required this.weeks,
    required this.trend,
    required this.scoreChange,
    required this.message,
    required this.riskLabel,
    required this.recommendations,
    required this.indicators,
  });

  double? get score => latest?.score;
  bool get hasData => latest != null;

  double? indicator(String key) => (indicators[key] as num?)?.toDouble();
}

class WlbService {
  final ApiService _api = ApiService();

  static DateTime mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<T?> _safe<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (e) {
      debugPrint('[WLB] request failed: $e');
      return null;
    }
  }

  WlbSurveyEntry? _entry(dynamic raw) {
    if (raw is! Map) return null;
    final week = DateTime.tryParse(raw['week_start_date']?.toString() ?? '');
    final score = (raw['score'] as num?)?.toDouble();
    if (week == null || score == null) return null;
    final ratings = <String, int>{};
    for (final d in kWlbDimensions) {
      final v = raw[d.field];
      if (v is num) ratings[d.field] = v.toInt();
    }
    return WlbSurveyEntry(weekStart: week, score: score, ratings: ratings);
  }

  Future<WlbOverview> load() async {
    final token = await _api.getToken();
    if (token == null) throw Exception('Not signed in');

    final results = await Future.wait<dynamic>([
      _safe(() => _api.getListWithAuth('/wlb/survey/history', token)),
      _safe(() => _api.getMapWithAuth('/wlb/analysis/trends?weeks=8', token)),
      _safe(() => _api.getMapWithAuth('/analytics/wellness/summary', token, allowNotFound: true)),
      _safe(() => _api.getMapWithAuth('/wlb/analysis/weekly', token, allowNotFound: true)),
    ]);

    final historyRaw = (results[0] as List<dynamic>?) ?? const [];
    final trendsRaw = results[1] as Map<String, dynamic>?;
    final summary = results[2] as Map<String, dynamic>?;
    final weekly = results[3] as Map<String, dynamic>?;

    // If every request failed, surface an error instead of a misleading
    // "no data yet" screen.
    if (results.every((r) => r == null)) {
      throw Exception('Unable to load work-life balance data.');
    }

    final history = historyRaw.map(_entry).whereType<WlbSurveyEntry>().toList()
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));

    final currentMonday = mondayOf(DateTime.now());
    final submitted = history.any((h) => mondayOf(h.weekStart) == currentMonday);

    final weeks = <WlbWeekPoint>[];
    for (final w in (trendsRaw?['weekly_data'] as List<dynamic>? ?? const [])) {
      if (w is! Map) continue;
      final start = DateTime.tryParse(w['week_start']?.toString() ?? '');
      if (start == null) continue;
      weeks.add(WlbWeekPoint(
        weekStart: start,
        score: (w['survey_score'] as num?)?.toDouble(),
        hours: (w['total_hours'] as num?)?.toDouble() ?? 0,
      ));
    }

    final wlb = summary?['wlb_analysis'] as Map<String, dynamic>?;
    final comparison = wlb?['weekly_comparison'] as Map<String, dynamic>?;
    final recs = <WlbRecommendation>[];
    for (final r in (summary?['wlb_recommendations'] as List<dynamic>? ?? const [])) {
      if (r is! Map) continue;
      final title = r['title']?.toString();
      if (title == null || title.isEmpty) continue;
      recs.add(WlbRecommendation(
        title: title,
        description: (r['action_step'] ?? r['description'] ?? '').toString(),
        reason: r['reason']?.toString(),
        category: r['category']?.toString(),
      ));
    }

    return WlbOverview(
      currentWeekStart: currentMonday,
      submittedThisWeek: submitted,
      latest: history.isNotEmpty ? history.first : null,
      history: history,
      weeks: weeks,
      trend: (trendsRaw?['trend'] ?? wlb?['trend'] ?? 'stable').toString(),
      scoreChange: (comparison?['score_change'] as num?)?.toDouble(),
      message: summary?['message']?.toString(),
      riskLabel: wlb?['risk_label']?.toString(),
      recommendations: recs,
      indicators: (weekly?['behavioral_indicators'] as Map<String, dynamic>?) ?? const {},
    );
  }

  /// Submits the weekly survey. Throws a readable message on conflict.
  Future<void> submitSurvey(Map<String, int> ratings, {DateTime? weekStart}) async {
    final token = await _api.getToken();
    if (token == null) throw Exception('Not signed in');
    final body = <String, dynamic>{
      'week_start_date': _fmt(weekStart ?? mondayOf(DateTime.now())),
      for (final d in kWlbDimensions) d.field: ratings[d.field],
    };
    try {
      await _api.postWithAuth('/wlb/survey', token, body);
    } catch (e) {
      if (e.toString().contains('409')) {
        throw Exception("This week's check-in has already been submitted.");
      }
      rethrow;
    }
  }
}
