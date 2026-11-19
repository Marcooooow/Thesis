class NotificationModel {
  final String id;
  final String type;
  final String title;
  final String message;
  final String? relatedEntityId;
  final bool isRead;
  final bool isActioned;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? actionedAt;

  NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.relatedEntityId,
    required this.isRead,
    required this.isActioned,
    required this.createdAt,
    this.readAt,
    this.actionedAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      relatedEntityId: json['related_entity_id'] as String?,
      isRead: json['is_read'] as bool,
      isActioned: json['is_actioned'] as bool,
      createdAt: _parseDateTime(json['created_at']),
      readAt: json['read_at'] != null
          ? _parseDateTime(json['read_at'])
          : null,
      actionedAt: json['actioned_at'] != null
          ? _parseDateTime(json['actioned_at'])
          : null,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is int) {
      // Unix timestamp in milliseconds
      return DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      // ISO 8601 string
      return DateTime.parse(value).toLocal();
    } else {
      throw FormatException('Unable to parse datetime: $value');
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'message': message,
      'related_entity_id': relatedEntityId,
      'is_read': isRead,
      'is_actioned': isActioned,
      'created_at': createdAt.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'actioned_at': actionedAt?.toIso8601String(),
    };
  }

  NotificationModel copyWith({
    String? id,
    String? type,
    String? title,
    String? message,
    String? relatedEntityId,
    bool? isRead,
    bool? isActioned,
    DateTime? createdAt,
    DateTime? readAt,
    DateTime? actionedAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      relatedEntityId: relatedEntityId ?? this.relatedEntityId,
      isRead: isRead ?? this.isRead,
      isActioned: isActioned ?? this.isActioned,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
      actionedAt: actionedAt ?? this.actionedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          title == other.title &&
          message == other.message &&
          relatedEntityId == other.relatedEntityId &&
          isRead == other.isRead &&
          isActioned == other.isActioned &&
          createdAt == other.createdAt &&
          readAt == other.readAt &&
          actionedAt == other.actionedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      type.hashCode ^
      title.hashCode ^
      message.hashCode ^
      relatedEntityId.hashCode ^
      isRead.hashCode ^
      isActioned.hashCode ^
      createdAt.hashCode ^
      readAt.hashCode ^
      actionedAt.hashCode;
}
