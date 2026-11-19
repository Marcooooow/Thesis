class EmployeeSchedule {
  final String id;
  final String profileId;
  final DateTime effectiveFrom;
  final DateTime? effectiveUntil;
  final List<String> workDays;
  final String shiftStart;
  final String shiftEnd;
  final String timezone;

  EmployeeSchedule({
    required this.id,
    required this.profileId,
    required this.effectiveFrom,
    this.effectiveUntil,
    required this.workDays,
    required this.shiftStart,
    required this.shiftEnd,
    required this.timezone,
  });

  factory EmployeeSchedule.fromJson(Map<String, dynamic> json) {
    return EmployeeSchedule(
      id: json['id'] as String,
      profileId: json['profile_id'] as String,
      effectiveFrom: DateTime.parse(json['effective_from']),
      effectiveUntil: json['effective_until'] != null ? DateTime.parse(json['effective_until']) : null,
      workDays: List<String>.from(json['work_days'] ?? []),
      shiftStart: json['shift_start'] as String,
      shiftEnd: json['shift_end'] as String,
      timezone: json['timezone'] as String? ?? 'UTC',
    );
  }
}

class AbsenceRecord {
  final String id;
  final String profileId;
  final DateTime absenceDate;
  final String scheduleId;
  final String classification; // UNREPORTED, LEAVE_APPROVED, EXCUSED, DISMISSED
  final String? leaveRequestId;
  final String notificationStatus;
  final DateTime? managerAcknowledgedAt;
  final String? notes;
  final String? employeeName;
  final String? department;
  final String? shiftStart;
  final String? shiftEnd;

  AbsenceRecord({
    required this.id,
    required this.profileId,
    required this.absenceDate,
    required this.scheduleId,
    required this.classification,
    this.leaveRequestId,
    required this.notificationStatus,
    this.managerAcknowledgedAt,
    this.notes,
    this.employeeName,
    this.department,
    this.shiftStart,
    this.shiftEnd,
  });

  factory AbsenceRecord.fromJson(Map<String, dynamic> json) {
    return AbsenceRecord(
      id: json['id'] as String,
      profileId: json['profile_id'] as String,
      absenceDate: DateTime.parse(json['absence_date']),
      scheduleId: json['schedule_id'] as String,
      classification: json['classification'] as String? ?? 'UNREPORTED',
      leaveRequestId: json['leave_request_id'] as String?,
      notificationStatus: json['notification_status'] as String? ?? 'PENDING',
      managerAcknowledgedAt: json['manager_acknowledged_at'] != null ? DateTime.parse(json['manager_acknowledged_at']) : null,
      notes: json['notes'] as String?,
      employeeName: json['employee_name'] as String?,
      department: json['department'] as String?,
      shiftStart: json['shift_start'] as String?,
      shiftEnd: json['shift_end'] as String?,
    );
  }
}

class LeaveRequest {
  final String id;
  final String profileId;
  final String leaveTypeId;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;
  final String status; // PENDING, APPROVED, REJECTED, CANCELLED
  final String? reviewerNote;
  final DateTime createdAt;

  LeaveRequest({
    required this.id,
    required this.profileId,
    required this.leaveTypeId,
    required this.startDate,
    required this.endDate,
    this.reason,
    required this.status,
    this.reviewerNote,
    required this.createdAt,
  });

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    return LeaveRequest(
      id: json['id'] as String,
      profileId: json['profile_id'] as String,
      leaveTypeId: json['leave_type_id'] as String,
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      reason: json['reason'] as String?,
      status: json['status'] as String? ?? 'PENDING',
      reviewerNote: json['reviewer_note'] as String?,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class AttendanceOverview {
  final EmployeeSchedule? schedule;
  final List<AbsenceRecord> absences;
  final List<LeaveRequest> leaveRequests;
  final Map<String, dynamic>? pendingRtw;

  AttendanceOverview({
    this.schedule,
    required this.absences,
    required this.leaveRequests,
    this.pendingRtw,
  });

  factory AttendanceOverview.fromJson(Map<String, dynamic> json) {
    return AttendanceOverview(
      schedule: json['schedule'] != null ? EmployeeSchedule.fromJson(json['schedule']) : null,
      absences: (json['absences'] as List<dynamic>? ?? [])
          .map((item) => AbsenceRecord.fromJson(item))
          .toList(),
      leaveRequests: (json['leave_requests'] as List<dynamic>? ?? [])
          .map((item) => LeaveRequest.fromJson(item))
          .toList(),
      pendingRtw: json['pending_rtw'] as Map<String, dynamic>?,
    );
  }
}

class LeaveType {
  final String id;
  final String name;
  final bool requiresDocumentation;
  final bool isActive;

  LeaveType({
    required this.id,
    required this.name,
    required this.requiresDocumentation,
    required this.isActive,
  });

  factory LeaveType.fromJson(Map<String, dynamic> json) {
    return LeaveType(
      id: json['id'] as String,
      name: json['name'] as String,
      requiresDocumentation: json['requires_documentation'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class PendingRtwInfo {
  final bool hasPending;
  final String? workSessionId;
  final String? absenceRecordId;
  final String? sessionEndedAt;

  PendingRtwInfo({
    required this.hasPending,
    this.workSessionId,
    this.absenceRecordId,
    this.sessionEndedAt,
  });

  factory PendingRtwInfo.fromJson(Map<String, dynamic> json) {
    return PendingRtwInfo(
      hasPending: json['has_pending'] as bool? ?? false,
      workSessionId: json['work_session_id'] as String?,
      absenceRecordId: json['absence_record_id'] as String?,
      sessionEndedAt: json['session_ended_at'] as String?,
    );
  }
}
