import '../../auth/services/api_service.dart';

class AdminAnalyticsService {
  final ApiService _apiService = ApiService();

  /// Get active employees count from /admin/user-counts
  Future<int> getActiveEmployeesCount(String token) async {
    try {
      final response = await _apiService.getMapWithAuth('/admin/user-counts', token);
      if (response == null) return 0;
      final employees = (response['employees'] as num?)?.toInt() ?? 0;
      final managers = (response['managers'] as num?)?.toInt() ?? 0;
      return employees + managers;
    } catch (_) {
      return 0;
    }
  }

  /// Get organization-wide today's focus ratio (admin-only endpoint)
  Future<Map<String, dynamic>> getTodayFocusRatio(String token, {String period = 'today'}) async {
    return await _apiService.getMapWithAuth(
          '/analytics/admin/today/focus-ratio?period=$period',
          token,
        ) ??
        {};
  }

  /// Get organization-wide weekly focus vs idle (admin-only endpoint)
  Future<List<dynamic>> getWeeklyFocusIdle(String token, {String period = 'this_week'}) async {
    return await _apiService.getListWithAuth(
      '/analytics/admin/weekly/focus-idle?period=$period',
      token,
    );
  }

  /// Get organization-wide focus rate (admin-only endpoint)
  Future<Map<String, dynamic>> getFocusRate(String token, {String period = 'today'}) async {
    return await _apiService.getMapWithAuth(
          '/analytics/admin/focus-rate?period=$period',
          token,
        ) ??
        {};
  }

  /// Get organization-wide today's recommendation analytics
  Future<Map<String, dynamic>> getTodayRecommendations(String token, {String period = 'today', String? startDate, String? endDate}) async {
    String query = '/analytics/admin/recommendations/today?period=$period';
    if (startDate != null) query += '&start_date=$startDate';
    if (endDate != null) query += '&end_date=$endDate';
    return await _apiService.getMapWithAuth(query, token) ?? {};
  }

  /// Get organization-wide weekly recommendation analytics
  Future<Map<String, dynamic>> getWeeklyRecommendations(String token, {String period = 'this_week', String? startDate, String? endDate}) async {
    String query = '/analytics/admin/recommendations/weekly?period=$period';
    if (startDate != null) query += '&start_date=$startDate';
    if (endDate != null) query += '&end_date=$endDate';
    return await _apiService.getMapWithAuth(query, token) ?? {};
  }

  /// Get organization-wide break patterns
  Future<Map<String, dynamic>> getBreakPatterns(String token, {String period = 'this_week', String? startDate, String? endDate}) async {
    String query = '/analytics/admin/break-patterns?period=$period';
    if (startDate != null) query += '&start_date=$startDate';
    if (endDate != null) query += '&end_date=$endDate';
    return await _apiService.getMapWithAuth(query, token) ?? {};
  }

  /// Get organization-wide team comparison chart data
  Future<Map<String, dynamic>> getTeamComparisonChart(String token, {String period = 'this_week', String? startDate, String? endDate}) async {
    String query = '/analytics/admin/team-comparison-chart?period=$period';
    if (startDate != null) query += '&start_date=$startDate';
    if (endDate != null) query += '&end_date=$endDate';
    return await _apiService.getMapWithAuth(query, token) ?? {};
  }

  /// Get organization-wide today's wellbeing analytics
  Future<Map<String, dynamic>> getTodayWellbeing(String token, {String period = 'today'}) async {
    return await _apiService.getMapWithAuth(
          '/analytics/admin/wellbeing/today?period=$period',
          token,
        ) ?? {};
  }

  /// Get organization-wide weekly wellbeing analytics
  Future<Map<String, dynamic>> getWeeklyWellbeing(String token, {String period = 'this_week'}) async {
    return await _apiService.getMapWithAuth(
          '/analytics/admin/wellbeing/weekly?period=$period',
          token,
        ) ?? {};
  }

  /// Get organization-wide weekly work hours (admin-only endpoint)
  Future<List<dynamic>> getWeeklyWorkHours(String token, {String period = 'this_week'}) async {
    return await _apiService.getListWithAuth(
      '/analytics/admin/weekly/work-hours?period=$period',
      token,
    );
  }

  /// Get what-changed comparison analytics
  Future<Map<String, dynamic>> getWhatChanged(String token, {String period = 'this_week'}) async {
    return await _apiService.getMapWithAuth(
          '/analytics/admin/what-changed?period=$period',
          token,
        ) ?? {};
  }
}
