import '../../auth/services/api_service.dart';

class AnalyticsService {
  final ApiService _apiService = ApiService();

  /// Get comprehensive summary metrics for a specific date range or today
  Future<Map<String, dynamic>> getTodaySummary(
    String token, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, String>{};
    if (startDate != null) {
      params['start_date'] = startDate.toIso8601String().split('T')[0];
    }
    if (endDate != null) {
      params['end_date'] = endDate.toIso8601String().split('T')[0];
    }
    final queryString = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';
    final response = await _apiService.getMapWithAuth('/analytics/today/summary$queryString', token);
    if (response == null) {
      return {};
    }
    return response;
  }

  /// Get focus ratio data for a specific date range
  Future<Map<String, double>> getFocusRatio(
    String token, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Build query parameters
    final params = <String, String>{};
    if (startDate != null) {
      params['start_date'] = startDate.toIso8601String().split(
        'T',
      )[0]; // Just the date part
    }
    if (endDate != null) {
      params['end_date'] = endDate.toIso8601String().split(
        'T',
      )[0]; // Just the date part
    }

    // Build query string
    final queryString = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';
    final endpoint = '/analytics/today/focus-ratio$queryString';

    final response = await _apiService.getMapWithAuth(endpoint, token);
    if (response == null) {
      return {'activeFocus': 0.0, 'nonActive': 0.0, 'idle': 0.0};
    }
    // Convert Map<String, dynamic> to Map<String, double>
    return response.map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    );
  }

  /// Get daily focus vs idle time for a specific date range
  Future<List<Map<String, dynamic>>> getDailyFocusIdle(
    String token, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Build query parameters
    final params = <String, String>{};
    if (startDate != null) {
      params['start_date'] = startDate.toIso8601String().split(
        'T',
      )[0]; // Just the date part
    }
    if (endDate != null) {
      params['end_date'] = endDate.toIso8601String().split(
        'T',
      )[0]; // Just the date part
    }

    // Build query string
    final queryString = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';
    final endpoint = '/analytics/weekly/focus-idle$queryString';

    final response = await _apiService.getListWithAuth(endpoint, token);
    return response.cast<Map<String, dynamic>>();
  }

  /// Direct endpoint fetch for admin analytics (bypass non-admin endpoint logic)
  Future<List<dynamic>> getListWithAuthDirect(String endpoint, String token) async {
    final response = await _apiService.getListWithAuth(endpoint, token);
    return response;
  }

  /// Get break analysis for a specific date range
  Future<Map<String, dynamic>> getBreakAnalysis(
    String token, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, String>{};
    if (startDate != null) {
      params['start_date'] = startDate.toIso8601String().split('T')[0];
    }
    if (endDate != null) {
      params['end_date'] = endDate.toIso8601String().split('T')[0];
    }
    final queryString = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';
    final response = await _apiService.getMapWithAuth('/analytics/break-analysis$queryString', token);
    return response ?? {};
  }

  /// Get daily progress summary for a specific date (YYYY-MM-DD)
  Future<Map<String, dynamic>> getDailyProgressSummary(
    String token, {
    String? date,
  }) async {
    final queryString = date != null ? '?date=$date' : '';
    final response = await _apiService.getMapWithAuth('/analytics/daily-summary$queryString', token);
    return response ?? {};
  }

  /// Get wellbeing check-in summary for a specific date range
  Future<Map<String, dynamic>> getWellbeingSummary(
    String token, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, String>{};
    if (startDate != null) {
      params['start_date'] = startDate.toIso8601String().split('T')[0];
    }
    if (endDate != null) {
      params['end_date'] = endDate.toIso8601String().split('T')[0];
    }
    final queryString = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';
    final response = await _apiService.getMapWithAuth('/analytics/wellbeing-summary$queryString', token);
    return response ?? {};
  }
  Future<List<Map<String, dynamic>>> getDailyWorkHours(
    String token, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Build query parameters
    final params = <String, String>{};
    if (startDate != null) {
      params['start_date'] = startDate.toIso8601String().split(
        'T',
      )[0]; // Just the date part
    }
    if (endDate != null) {
      params['end_date'] = endDate.toIso8601String().split(
        'T',
      )[0]; // Just the date part
    }

    // Build query string
    final queryString = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';
    final endpoint = '/analytics/weekly/work-hours$queryString';

    final response = await _apiService.getListWithAuth(endpoint, token);
    return response.cast<Map<String, dynamic>>();
  }

  /// Get focus rate (percentage) for a specific date range
  Future<double> getFocusRate(
    String token, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Build query parameters
    final params = <String, String>{};
    if (startDate != null) {
      params['start_date'] = startDate.toIso8601String().split(
        'T',
      )[0]; // Just the date part
    }
    if (endDate != null) {
      params['end_date'] = endDate.toIso8601String().split(
        'T',
      )[0]; // Just the date part
    }

    // Build query string
    final queryString = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';
    final endpoint = '/analytics/focus-rate$queryString';

    final response = await _apiService.getMapWithAuth(endpoint, token);
    if (response == null) {
      return 0.0;
    }
    return (response['rate'] as num?)?.toDouble() ?? 0.0;
  }
}
