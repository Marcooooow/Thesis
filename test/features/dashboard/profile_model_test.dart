import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/features/dashboard/models/profile_model.dart';

void main() {
  final testJson = {
    'id': '123e4567-e89b-12d3-a456-426614174000',
    'full_name': 'John Doe',
    'phone_number': '123-456-7890',
    'job_role': 'Software Engineer',
    'industry': 'Technology',
    'years_of_experience': 5,
    'age': 30,
    'gender': 'Male',
    'education_attainment': 'Bachelor\'s Degree',
    'marital_status': 'Single',
    'target_daily_hours': 8,
    'shift_start_time': '09:00',
    'shift_end_time': '17:00',
    'work_days': ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
    'hire_date': '2020-01-15',
    'department': 'Engineering',
    'is_test_data': false,
    'created_at': '2023-01-01T00:00:00Z',
    'updated_at': '2023-01-02T00:00:00Z',
  };

  test('Profile.fromJson correctly parses JSON', () {
    final profile = Profile.fromJson(testJson);
    expect(profile.id, testJson['id']);
    expect(profile.fullName, testJson['full_name']);
    expect(profile.phoneNumber, testJson['phone_number']);
    expect(profile.jobRole, testJson['job_role']);
    expect(profile.industry, testJson['industry']);
    expect(profile.yearsOfExperience, testJson['years_of_experience']);
    expect(profile.age, testJson['age']);
    expect(profile.gender, testJson['gender']);
    expect(profile.educationAttainment, testJson['education_attainment']);
    expect(profile.maritalStatus, testJson['marital_status']);
    expect(profile.targetDailyHours, testJson['target_daily_hours']);
    expect(profile.shiftStartTime, testJson['shift_start_time']);
    expect(profile.shiftEndTime, testJson['shift_end_time']);
    expect(profile.workDays, testJson['work_days']);
    expect(profile.hireDate, testJson['hire_date']);
    expect(profile.department, testJson['department']);
    expect(profile.isTestData, testJson['is_test_data']);
    expect(profile.createdAt,
        DateTime.parse(testJson['created_at'] as String));
    expect(profile.updatedAt,
        DateTime.parse(testJson['updated_at'] as String));
  });

  test('Profile.toJson correctly converts to JSON', () {
    final profile = Profile.fromJson(testJson);
    final json = profile.toJson();
    expect(json['id'], testJson['id']);
    expect(json['full_name'], testJson['full_name']);
    expect(json['phone_number'], testJson['phone_number']);
    expect(json['job_role'], testJson['job_role']);
    expect(json['industry'], testJson['industry']);
    expect(json['years_of_experience'], testJson['years_of_experience']);
    expect(json['age'], testJson['age']);
    expect(json['gender'], testJson['gender']);
    expect(json['education_attainment'], testJson['education_attainment']);
    expect(json['marital_status'], testJson['marital_status']);
    expect(json['target_daily_hours'], testJson['target_daily_hours']);
    expect(json['shift_start_time'], testJson['shift_start_time']);
    expect(json['shift_end_time'], testJson['shift_end_time']);
    expect(json['work_days'], testJson['work_days']);
    expect(json['hire_date'], testJson['hire_date']);
    expect(json['department'], testJson['department']);
    expect(json['is_test_data'], testJson['is_test_data']);
    expect(json['created_at'],
        (DateTime.parse(testJson['created_at'] as String)).toIso8601String());
    expect(json['updated_at'],
        (DateTime.parse(testJson['updated_at'] as String)).toIso8601String());
  });
}