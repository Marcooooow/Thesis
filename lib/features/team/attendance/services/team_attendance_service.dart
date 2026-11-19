import 'package:flutter/foundation.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/attendance/models/attendance_model.dart';
import '../models/team_attendance_model.dart';

class TeamAttendanceService {
  final ApiService _apiService = ApiService();

  Future<List<AbsenceRecord>> fetchTeamAbsences(String token, {String? startDate, String? endDate, String? classification, bool? acknowledged}) async {
    try {
      String endpoint = '/manager/absences';
      final params = <String>[];
      if (startDate != null) params.add('start_date=$startDate');
      if (endDate != null) params.add('end_date=$endDate');
      if (classification != null) params.add('classification=$classification');
      if (acknowledged != null) params.add('acknowledged=$acknowledged');
      if (params.isNotEmpty) endpoint += '?${params.join('&')}';

      final response = await _apiService.getListWithAuth(endpoint, token);
      return response.map((item) => AbsenceRecord.fromJson(item)).toList();
    } catch (e) {
      debugPrint('[TEAM_ATTENDANCE_ERROR] fetchTeamAbsences: $e');
      rethrow;
    }
  }

  Future<AbsenceRecord> acknowledgeAbsence(String token, String absenceId, String classification, String? notes) async {
    final Map<String, dynamic> body = {
      'classification': classification.toUpperCase(),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    };
    final response = await _apiService.patchWithAuth('/manager/absences/$absenceId/acknowledge', token, body);
    return AbsenceRecord.fromJson(response);
  }

  Future<List<LeaveRequest>> fetchTeamLeaveRequests(String token, {String? status, String? profileId}) async {
    try {
      String endpoint = '/manager/leave/requests';
      final params = <String>[];
      if (status != null) params.add('status=$status');
      if (profileId != null) params.add('profile_id=$profileId');
      if (params.isNotEmpty) endpoint += '?${params.join('&')}';

      final response = await _apiService.getListWithAuth(endpoint, token);
      return response.map((item) => LeaveRequest.fromJson(item)).toList();
    } catch (e) {
      debugPrint('[TEAM_ATTENDANCE_ERROR] fetchTeamLeaveRequests: $e');
      rethrow;
    }
  }

  Future<LeaveRequest> reviewLeaveRequest(String token, String requestId, bool approve, String? reviewerNote) async {
    final Map<String, dynamic> body = {
      'approve': approve,
      if (reviewerNote != null && reviewerNote.isNotEmpty) 'reviewer_note': reviewerNote,
    };
    final response = await _apiService.patchWithAuth('/manager/leave/requests/$requestId/review', token, body);
    return LeaveRequest.fromJson(response);
  }

  Future<List<TeamRtwRecord>> fetchTeamRtw(String token) async {
    try {
      final response = await _apiService.getListWithAuth('/manager/return-to-work/team', token);
      return response.map((item) => TeamRtwRecord.fromJson(item)).toList();
    } catch (e) {
      debugPrint('[TEAM_ATTENDANCE_ERROR] fetchTeamRtw: $e');
      rethrow;
    }
  }
}
