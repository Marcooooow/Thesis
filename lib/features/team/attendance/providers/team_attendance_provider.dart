import 'package:flutter/foundation.dart';
import 'package:intellibreak/features/attendance/models/attendance_model.dart';
import '../models/team_attendance_model.dart';
import '../services/team_attendance_service.dart';

class TeamAttendanceProvider extends ChangeNotifier {
  final TeamAttendanceService _service = TeamAttendanceService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  List<AbsenceRecord> _absences = [];
  List<AbsenceRecord> get absences => _absences;

  List<LeaveRequest> _leaveRequests = [];
  List<LeaveRequest> get leaveRequests => _leaveRequests;

  List<TeamRtwRecord> _rtwRecords = [];
  List<TeamRtwRecord> get rtwRecords => _rtwRecords;

  Future<void> loadTeamData(String token, {String? absenceStatus, String? leaveStatus}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.fetchTeamAbsences(token, acknowledged: absenceStatus == 'acknowledged' ? true : (absenceStatus == 'unacknowledged' ? false : null)),
        _service.fetchTeamLeaveRequests(token, status: leaveStatus),
        _service.fetchTeamRtw(token),
      ]);

      _absences = results[0] as List<AbsenceRecord>;
      _leaveRequests = results[1] as List<LeaveRequest>;
      _rtwRecords = results[2] as List<TeamRtwRecord>;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> acknowledgeAbsence(String token, String absenceId, String classification, String? notes) async {
    try {
      final updated = await _service.acknowledgeAbsence(token, absenceId, classification, notes);
      final index = _absences.indexWhere((a) => a.id == absenceId);
      if (index != -1) {
        _absences[index] = updated;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> reviewLeaveRequest(String token, String requestId, bool approve, String? reviewerNote) async {
    try {
      final updated = await _service.reviewLeaveRequest(token, requestId, approve, reviewerNote);
      final index = _leaveRequests.indexWhere((r) => r.id == requestId);
      if (index != -1) {
        _leaveRequests[index] = updated;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }
}
