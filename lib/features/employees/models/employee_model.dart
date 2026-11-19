class Employee {
  final String id;
  final String fullName;
  final String email;
  final bool isActive;
  final String? teamName;
  final String? teamId;
  final String role;

  Employee({
    required this.id,
    required this.fullName,
    required this.email,
    required this.isActive,
    this.teamName,
    this.teamId,
    this.role = 'EMPLOYEE',
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      isActive: json['is_active'] as bool,
      teamName: json['team_name'] as String?,
      teamId: json['team_id'] != null ? json['team_id'].toString() : null,
      role: json['role'] as String? ?? 'EMPLOYEE',
    );
  }
}
