import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/features/attendance/models/attendance_model.dart';

void main() {
  group('Attendance Models Tests', () {
    test('EmployeeSchedule.fromJson parses correctly', () {
      final json = {
        'id': 'sched-123',
        'profile_id': 'prof-456',
        'effective_from': '2026-11-01',
        'effective_until': null,
        'work_days': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
        'shift_start': '09:00:00',
        'shift_end': '17:00:00',
        'timezone': 'Asia/Manila',
      };

      final schedule = EmployeeSchedule.fromJson(json);
      expect(schedule.id, 'sched-123');
      expect(schedule.profileId, 'prof-456');
      expect(schedule.effectiveFrom.year, 2026);
      expect(schedule.effectiveUntil, null);
      expect(schedule.workDays.length, 5);
      expect(schedule.shiftStart, '09:00:00');
      expect(schedule.shiftEnd, '17:00:00');
      expect(schedule.timezone, 'Asia/Manila');
    });

    test('AbsenceRecord.fromJson parses correctly', () {
      final json = {
        'id': 'abs-1',
        'profile_id': 'prof-456',
        'absence_date': '2026-11-02',
        'schedule_id': 'sched-123',
        'classification': 'UNREPORTED',
        'notification_status': 'DISPATCHED',
      };

      final record = AbsenceRecord.fromJson(json);
      expect(record.id, 'abs-1');
      expect(record.classification, 'UNREPORTED');
      expect(record.notificationStatus, 'DISPATCHED');
      expect(record.absenceDate.day, 2);
    });

    test('LeaveRequest.fromJson parses correctly', () {
      final json = {
        'id': 'leave-1',
        'profile_id': 'prof-456',
        'leave_type_id': 'type-1',
        'start_date': '2026-11-10',
        'end_date': '2026-11-12',
        'reason': 'Vacation',
        'status': 'PENDING',
        'created_at': '2026-11-01T10:00:00Z',
      };

      final req = LeaveRequest.fromJson(json);
      expect(req.id, 'leave-1');
      expect(req.reason, 'Vacation');
      expect(req.status, 'PENDING');
      expect(req.startDate.day, 10);
    });

    test('LeaveType.fromJson parses correctly', () {
      final json = {
        'id': 'type-1',
        'name': 'Sick Leave',
        'requires_documentation': true,
        'is_active': true,
      };

      final lt = LeaveType.fromJson(json);
      expect(lt.id, 'type-1');
      expect(lt.name, 'Sick Leave');
      expect(lt.requiresDocumentation, true);
      expect(lt.isActive, true);
    });
  });
}
