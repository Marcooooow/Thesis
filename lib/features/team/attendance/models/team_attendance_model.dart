
class TeamRtwRecord {
  final String id;
  final String profileId;
  final String? absenceReasonCategory;
  final bool? wantsManagerSupport;
  final DateTime submittedAt;

  TeamRtwRecord({
    required this.id,
    required this.profileId,
    this.absenceReasonCategory,
    this.wantsManagerSupport,
    required this.submittedAt,
  });

  factory TeamRtwRecord.fromJson(Map<String, dynamic> json) {
    return TeamRtwRecord(
      id: json['id'] as String,
      profileId: json['profile_id'] as String,
      absenceReasonCategory: json['absence_reason_category'] as String?,
      wantsManagerSupport: json['wants_manager_support'] as bool?,
      submittedAt: DateTime.parse(json['submitted_at']),
    );
  }
}
