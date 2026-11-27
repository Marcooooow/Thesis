import 'package:intellibreak/features/auth/services/api_service.dart';

class AdminAnalyticsService {
  final ApiService _apiService = ApiService();

  /// Get total user count from /admin/user-counts
  Future<int?> getUserCount(String token) async {
    try {
      final response = await _apiService.getMapWithAuth('/admin/user-counts', token);
      if (response == null) return null;
      return response['count'] ?? response['total'] ?? response['employees'] ?? 0;
    } catch (_) {
      return null;
    }
  }

  /// Get active sessions count from /work/admin/active-sessions-count
  Future<int?> getActiveSessionsCount(String token) async {
    try {
      final response = await _apiService.getMapWithAuth('/work/admin/active-sessions-count', token);
      if (response == null) return null;
      return response['count'] ?? response['active_sessions'] ?? 0;
    } catch (_) {
      return null;
    }
  }

  /// Get focus rate (percentage) from /analytics/admin/focus-rate
  Future<double?> getFocusRate(String token, {String? startDate, String? endDate, String? period}) async {
    try {
      final params = <String, String>{};
      if (period != null) params['period'] = period;
      if (startDate != null) params['start_date'] = startDate;
      if (endDate != null) params['end_date'] = endDate;
      final endpoint = params.isNotEmpty
          ? '/analytics/admin/focus-rate?${params.entries.map((e) => "${e.key}=${e.value}").join("&")}'
          : '/analytics/admin/focus-rate';
      final response = await _apiService.getMapWithAuth(endpoint, token);
      if (response == null) return null;
      return (response['rate'] as num?)?.toDouble();
    } catch (_) {
      return null;
    }
  }

  /// Get weekly work hours from /analytics/admin/weekly/work-hours
  Future<List<Map<String, dynamic>>?> getWeeklyWorkHours(String token, {String? startDate, String? endDate, String? period}) async {
    try {
      final params = <String, String>{};
      if (period != null) params['period'] = period;
      if (startDate != null) params['start_date'] = startDate;
      if (endDate != null) params['end_date'] = endDate;
      final endpoint = params.isNotEmpty
          ? '/analytics/admin/weekly/work-hours?${params.entries.map((e) => "${e.key}=${e.value}").join("&")}'
          : '/analytics/admin/weekly/work-hours';
      final response = await _apiService.getListWithAuth(endpoint, token);
      return response.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  /// Get weekly focus/idle from /analytics/admin/weekly/focus-idle
  Future<List<Map<String, dynamic>>?> getFocusIdle(String token, {String? startDate, String? endDate, String? period}) async {
    try {
      final params = <String, String>{};
      if (period != null) params['period'] = period;
      if (startDate != null) params['start_date'] = startDate;
      if (endDate != null) params['end_date'] = endDate;
      final endpoint = params.isNotEmpty
          ? '/analytics/admin/weekly/focus-idle?${params.entries.map((e) => "${e.key}=${e.value}").join("&")}'
          : '/analytics/admin/weekly/focus-idle';
      final response = await _apiService.getListWithAuth(endpoint, token);
      return response.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  /// Get active breaks count from /work/admin/active-breaks-count
  Future<int?> getActiveBreaksCount(String token) async {
    try {
      final response = await _apiService.getMapWithAuth('/work/admin/active-breaks-count', token);
      if (response == null) return null;
      return response['count'] ?? response['active_breaks'] ?? 0;
    } catch (_) {
      return null;
    }
  }

  /// Get team comparison from /analytics/admin/team-comparison
  Future<Map<String, dynamic>?> getTeamComparison(String token, {String? period, String? startDate, String? endDate}) async {
    try {
      final params = <String, String>{};
      if (period != null) params['period'] = period;
      if (startDate != null) params['start_date'] = startDate;
      if (endDate != null) params['end_date'] = endDate;
      final endpoint = params.isNotEmpty
          ? '/analytics/admin/team-comparison?${params.entries.map((e) => "${e.key}=${e.value}").join("&")}'
          : '/analytics/admin/team-comparison';
      final response = await _apiService.getMapWithAuth(endpoint, token);
      return response;
    } catch (_) {
      return null;
    }
  }

  /// Get recommendation effectiveness from /analytics/admin/recommendation-effectiveness
  Future<Map<String, dynamic>?> getRecommendationEffectiveness(String token, {String? period, String? startDate, String? endDate, String? teamId}) async {
    try {
      final params = <String, String>{};
      if (period != null) params['period'] = period;
      if (startDate != null) params['start_date'] = startDate;
      if (endDate != null) params['end_date'] = endDate;
      if (teamId != null) params['team_id'] = teamId;
      final endpoint = params.isNotEmpty
          ? '/analytics/admin/recommendation-effectiveness?${params.entries.map((e) => "${e.key}=${e.value}").join("&")}'
          : '/analytics/admin/recommendation-effectiveness';
      final response = await _apiService.getMapWithAuth(endpoint, token);
      return response;
    } catch (_) {
      return null;
    }
  }

  /// Get complete organization reports preview covering all 8 sections
  Future<Map<String, dynamic>?> getReportsPreview(String token, {String? period}) async {
    try {
      final params = <String, String>{};
      if (period != null) params['period'] = period;
      final endpoint = params.isNotEmpty
          ? '/analytics/admin/reports/preview?${params.entries.map((e) => "${e.key}=${e.value}").join("&")}'
          : '/analytics/admin/reports/preview';
      final response = await _apiService.getMapWithAuth(endpoint, token);
      return response;
    } catch (_) {
      return null;
    }
  }

  /// Get privacy-protected next-week projections for the admin's authorized organization/team scope.
  Future<Map<String, dynamic>?> getPredictiveOutlook(String token) async {
    try {
      return await _apiService.getMapWithAuth('/manager/analytics/predictive-outlook', token);
    } catch (_) {
      return null;
    }
  }
}
