/// Represents a team in the system.
class Team {
  final String id;
  final String name;
  final String? description;
  final String managerId;
  final String managerName;
  final int memberCount;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Team({
    required this.id,
    required this.name,
    this.description,
    required this.managerId,
    required this.managerName,
    required this.memberCount,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a Team from API response JSON.
  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      managerId: json['manager_id'] as String,
      managerName: json['manager_name'] as String,
      memberCount: json['member_count'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert Team to JSON for API requests.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'manager_id': managerId,
    'manager_name': managerName,
    'member_count': memberCount,
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

/// Represents a team member with their role and status.
class TeamMember {
  final String userId;
  final String profileId;
  final String userName;
  final String userEmail;
  final String role;
  final DateTime joinedAt;
  final bool isCurrent;
  final Map<String, dynamic>? activeWorkSession;
  final Map<String, dynamic>? activeBreak;
  final String? teamName;
  final String? managerName;

  TeamMember({
    required this.userId,
    required this.profileId,
    required this.userName,
    required this.userEmail,
    required this.role,
    required this.joinedAt,
    required this.isCurrent,
    this.activeWorkSession,
    this.activeBreak,
    this.teamName,
    this.managerName,
  });

  /// Create a TeamMember from API response JSON.
  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      userId: json['id'] as String,
      profileId: json['profile_id'] as String? ?? '',
      userName: json['full_name'] as String,
      userEmail: json['email'] as String,
      role: json['role'] as String? ?? 'EMPLOYEE',
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : DateTime.now(),
      isCurrent: json['is_current'] as bool? ?? true,
      activeWorkSession: json['active_work_session'] as Map<String, dynamic>?,
      activeBreak: json['active_break'] as Map<String, dynamic>?,
      teamName: json['team_name'] as String?,
      managerName: json['manager_name'] as String?,
    );
  }

  /// Convert TeamMember to JSON for API requests.
  Map<String, dynamic> toJson() => {
    'id': userId,
    'profile_id': profileId,
    'full_name': userName,
    'email': userEmail,
    'role': role,
    'joined_at': joinedAt.toIso8601String(),
    'is_current': isCurrent,
  };

  String get status {
    if (activeBreak != null && activeBreak!['ended_at'] == null) {
      return 'On Break';
    } else if (activeWorkSession != null && activeWorkSession!['ended_at'] == null) {
      return 'Working';
    } else {
      return 'Offline';
    }
  }

  String get hoursTodayText {
    if (activeWorkSession != null && activeWorkSession!['started_at'] != null) {
      try {
        final start = DateTime.parse(activeWorkSession!['started_at'] as String);
        final diff = DateTime.now().difference(start);
        final hours = diff.inMinutes / 60.0;
        return '${hours.toStringAsFixed(1)} hrs today';
      } catch (_) {}
    }
    return '0.0 hrs today';
  }

  String get focusText {
    if (activeWorkSession != null && activeWorkSession!['focus_rate'] != null) {
      final focus = (activeWorkSession!['focus_rate'] as num).toDouble();
      return 'Focus: ${focus.toStringAsFixed(0)}%';
    }
    return 'Focus: Unavailable';
  }
}

/// Represents a team invitation sent to an employee.
class TeamInvitation {
  final String id;
  final String teamId;
  final String email;
  final String invitedBy;
  final String role;
  final String status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? acceptedAt;
  final DateTime? declinedAt;

  TeamInvitation({
    required this.id,
    required this.teamId,
    required this.email,
    required this.invitedBy,
    required this.role,
    required this.status,
    required this.createdAt,
    this.expiresAt,
    this.acceptedAt,
    this.declinedAt,
  });

  /// Create a TeamInvitation from API response JSON.
  factory TeamInvitation.fromJson(Map<String, dynamic> json) {
    return TeamInvitation(
      id: json['id'] as String,
      teamId: json['team_id'] as String,
      email: json['email'] as String,
      invitedBy: json['invited_by'] as String,
      role: json['role'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      declinedAt: json['declined_at'] != null
          ? DateTime.parse(json['declined_at'] as String)
          : null,
    );
  }

  /// Convert TeamInvitation to JSON for API requests.
  Map<String, dynamic> toJson() => {
    'id': id,
    'team_id': teamId,
    'email': email,
    'invited_by': invitedBy,
    'role': role,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'expires_at': expiresAt?.toIso8601String(),
    'accepted_at': acceptedAt?.toIso8601String(),
    'declined_at': declinedAt?.toIso8601String(),
  };

  /// Check if invitation is still pending.
  bool get isPending => status == 'pending';

  /// Check if invitation has been accepted.
  bool get isAccepted => status == 'accepted';

  /// Check if invitation has been declined.
  bool get isDeclined => status == 'declined';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamInvitation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
