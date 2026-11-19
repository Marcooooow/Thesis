import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intellibreak/features/auth/services/api_service.dart';
import '../models/wellbeing_models.dart';

class WellbeingService {
  final ApiService _apiService = ApiService();

  Future<WeeklyOverviewResponse> getWeeklyOverview({DateTime? weekStart, String? teamId}) async {
    final token = await _apiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final queryParams = <String, String>{};
    if (weekStart != null) {
      queryParams['week_start'] = weekStart.toIso8601String().split('T')[0];
    }
    if (teamId != null) {
      queryParams['team_id'] = teamId;
    }

    final uri = Uri.parse('${ApiService.baseUrl}/manager/wellbeing/weekly').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return WeeklyOverviewResponse.fromJson(data);
    } else {
      throw Exception('Failed to load weekly well-being overview: ${response.body}');
    }
  }

  Future<EmployeeDetailResponse> getEmployeeDetail(String employeeId, {DateTime? weekStart}) async {
    final token = await _apiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final queryParams = <String, String>{};
    if (weekStart != null) {
      queryParams['week_start'] = weekStart.toIso8601String().split('T')[0];
    }

    final uri = Uri.parse('${ApiService.baseUrl}/manager/wellbeing/$employeeId/detail').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return EmployeeDetailResponse.fromJson(data);
    } else {
      throw Exception('Failed to load employee well-being detail: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getTeamWellnessAdvisor({String? teamId, DateTime? startDate, DateTime? endDate}) async {
    final token = await _apiService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final queryParams = <String, String>{};
    if (teamId != null) queryParams['team_id'] = teamId;
    if (startDate != null) queryParams['start_date'] = startDate.toIso8601String().split('T')[0];
    if (endDate != null) queryParams['end_date'] = endDate.toIso8601String().split('T')[0];

    final uri = Uri.parse('${ApiService.baseUrl}/manager/wellbeing/advisor').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load team wellness advisor report: ${response.body}');
    }
  }
}

