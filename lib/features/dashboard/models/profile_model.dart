class Profile {
  final String id;
  final String fullName;
  final String? phoneNumber;
  final String? jobRole;
  final String? industry;
  final int? yearsOfExperience;
  final int? age;
  final String? gender;
  final String? educationAttainment;
  final String? maritalStatus;
  final int? targetDailyHours;
  final String? shiftStartTime;
  final String? shiftEndTime;
  final List<String>? workDays;
  final String? hireDate;
  final String? department;
  final bool isTestData;
  final DateTime createdAt;
  final DateTime updatedAt;
final String? profileImageUrl;

  Profile({
    required this.id,
    required this.fullName,
    this.phoneNumber,
    this.jobRole,
    this.industry,
    this.yearsOfExperience,
    this.age,
    this.gender,
    this.educationAttainment,
    this.maritalStatus,
    this.targetDailyHours,
    this.shiftStartTime,
    this.shiftEndTime,
    this.workDays,
    this.hireDate,
    this.department,
    required this.isTestData,
    required this.createdAt,
    required this.updatedAt,
    this.profileImageUrl,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      phoneNumber: json['phone_number'] as String?,
      jobRole: json['job_role'] as String?,
      industry: json['industry'] as String?,
      yearsOfExperience: json['years_of_experience'] as int?,
      age: json['age'] as int?,
      gender: json['gender'] as String?,
      educationAttainment: json['education_attainment'] as String?,
      maritalStatus: json['marital_status'] as String?,
      targetDailyHours: json['target_daily_hours'] as int?,
      shiftStartTime: json['shift_start_time'] as String?,
      shiftEndTime: json['shift_end_time'] as String?,
      workDays: (json['work_days'] as List<dynamic>?)?.map((e) => e as String).toList(),
      hireDate: json['hire_date'] as String?,
      department: json['department'] as String?,
      isTestData: json['is_test_data'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      profileImageUrl: json['profile_image_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'job_role': jobRole,
      'industry': industry,
      'years_of_experience': yearsOfExperience,
      'age': age,
      'gender': gender,
      'education_attainment': educationAttainment,
      'marital_status': maritalStatus,
      'target_daily_hours': targetDailyHours,
      'shift_start_time': shiftStartTime,
      'shift_end_time': shiftEndTime,
      'work_days': workDays,
      'hire_date': hireDate,
      'department': department,
      'is_test_data': isTestData,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'profile_image_url': profileImageUrl,
    };
  }

  // Create a copyWith method for easy updating
  Profile copyWith({
    String? id,
    String? fullName,
    String? phoneNumber,
    String? jobRole,
    String? industry,
    int? yearsOfExperience,
    int? age,
    String? gender,
    String? educationAttainment,
    String? maritalStatus,
    int? targetDailyHours,
    String? shiftStartTime,
    String? shiftEndTime,
    List<String>? workDays,
    String? hireDate,
    String? department,
    bool? isTestData,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? profileImageUrl,
  }) {
    return Profile(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      jobRole: jobRole ?? this.jobRole,
      industry: industry ?? this.industry,
      yearsOfExperience: yearsOfExperience ?? this.yearsOfExperience,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      educationAttainment: educationAttainment ?? this.educationAttainment,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      targetDailyHours: targetDailyHours ?? this.targetDailyHours,
      shiftStartTime: shiftStartTime ?? this.shiftStartTime,
      shiftEndTime: shiftEndTime ?? this.shiftEndTime,
      workDays: workDays ?? this.workDays,
      hireDate: hireDate ?? this.hireDate,
      department: department ?? this.department,
      isTestData: isTestData ?? this.isTestData,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    );
  }
}