import 'package:flutter/foundation.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import '../models/attendance_model.dart';

class AttendanceService {
  final ApiService _apiService = ApiService();

  Future<AttendanceOverview> fetchMyAttendance(String token, {String? startDate, String? endDate}) async {
    try {
      debugPrint('[ATTENDANCE_HTTP] GET /attendance/my starting');
      String endpoint = '/attendance/my';
      final queryParams = <String>[];
      if (startDate != null) queryParams.add('start_date=$startDate');
      if (endDate != null) queryParams.add('end_date=$endDate');
      if (queryParams.isNotEmpty) {
        endpoint += '?${queryParams.join('&')}';
      }

      final response = await _apiService.getMapWithAuth(endpoint, token);
      if (response == null) {
        throw Exception('Failed to load attendance: empty response.');
      }

      return AttendanceOverview.fromJson(response);
    } catch (e) {
      debugPrint('[ATTENDANCE_ERROR] Exception: $e');
      rethrow;
    }
  }

  Future<EmployeeSchedule?> fetchCurrentSchedule(String token, String profileId) async {
    try {
      debugPrint('[ATTENDANCE_HTTP] GET /schedules/$profileId/current starting');
      final response = await _apiService.getMapWithAuth('/schedules/$profileId/current', token);
      if (response == null) return null;
      return EmployeeSchedule.fromJson(response);
    } catch (e) {
      debugPrint('[ATTENDANCE_ERROR] fetchCurrentSchedule: $e');
      return null;
    }
  }

  Future<List<LeaveType>> fetchLeaveTypes(String token) async {
    try {
      final response = await _apiService.getListWithAuth('/leave/types', token);
      return response.map((item) => LeaveType.fromJson(item)).toList();
    } catch (e) {
      debugPrint('[ATTENDANCE_ERROR] fetchLeaveTypes: $e');
      return [];
    }
  }

  Future<void> submitLeaveRequest(String token, String leaveTypeId, String startDate, String endDate, String? reason) async {
    final Map<String, dynamic> body = {
      'leave_type_id': leaveTypeId,
      'start_date': startDate,
      'end_date': endDate,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    };
    await _apiService.postWithAuth('/leave/requests', token, body);
  }

  Future<void> cancelLeaveRequest(String token, String requestId) async {
    await _apiService.patchWithAuth('/leave/requests/$requestId/cancel', token, <String, dynamic>{});
  }

  Future<PendingRtwInfo> checkPendingRtw(String token) async {
    try {
      final response = await _apiService.getMapWithAuth('/return-to-work/pending', token);
      if (response == null) return PendingRtwInfo(hasPending: false);
      return PendingRtwInfo.fromJson(response);
    } catch (e) {
      debugPrint('[ATTENDANCE_ERROR] checkPendingRtw: $e');
      return PendingRtwInfo(hasPending: false);
    }
  }

  Future<void> submitRtwCheckin(String token, Map<String, dynamic> data) async {
    await _apiService.postWithAuth('/return-to-work/checkin', token, data);
  }
}
