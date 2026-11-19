import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/features/notifications/models/notification_model.dart';

void main() {
  group('NotificationModel', () {
    test('creates NotificationModel from JSON with all fields', () {
      final json = {
        'id': 'notif-1',
        'type': 'team_invitation',
        'title': 'Team Invitation',
        'message': 'You have been invited to join a team',
        'related_entity_id': 'team-123',
        'is_read': false,
        'is_actioned': false,
        'created_at': '2026-09-17T10:30:00Z',
        'read_at': null,
        'actioned_at': null,
      };

      final notification = NotificationModel.fromJson(json);

      expect(notification.id, 'notif-1');
      expect(notification.type, 'team_invitation');
      expect(notification.title, 'Team Invitation');
      expect(notification.message, 'You have been invited to join a team');
      expect(notification.relatedEntityId, 'team-123');
      expect(notification.isRead, false);
      expect(notification.isActioned, false);
      expect(notification.readAt, null);
      expect(notification.actionedAt, null);
    });

    test('parses DateTime fields correctly from ISO 8601 strings', () {
      final json = {
        'id': 'notif-2',
        'type': 'test',
        'title': 'Test',
        'message': 'Test',
        'related_entity_id': null,
        'is_read': true,
        'is_actioned': true,
        'created_at': '2026-09-17T10:30:00Z',
        'read_at': '2026-09-17T11:00:00Z',
        'actioned_at': '2026-09-17T11:05:00Z',
      };

      final notification = NotificationModel.fromJson(json);

      expect(notification.createdAt.year, 2026);
      expect(notification.createdAt.month, 9);
      expect(notification.createdAt.day, 17);
      expect(notification.readAt, isNotNull);
      expect(notification.actionedAt, isNotNull);
    });

    test('handles nullable fields correctly', () {
      final json = {
        'id': 'notif-3',
        'type': 'notification',
        'title': 'Title',
        'message': 'Message',
        'related_entity_id': null,
        'is_read': false,
        'is_actioned': false,
        'created_at': '2026-09-17T10:30:00Z',
        'read_at': null,
        'actioned_at': null,
      };

      final notification = NotificationModel.fromJson(json);

      expect(notification.relatedEntityId, null);
      expect(notification.readAt, null);
      expect(notification.actionedAt, null);
    });

    test('copyWith creates new instance with updated fields', () {
      final notification = NotificationModel(
        id: 'notif-1',
        type: 'test',
        title: 'Title',
        message: 'Message',
        relatedEntityId: 'entity-1',
        isRead: false,
        isActioned: false,
        createdAt: DateTime(2026, 9, 17),
      );

      final updated = notification.copyWith(isRead: true);

      expect(updated.id, notification.id);
      expect(updated.isRead, true);
      expect(notification.isRead, false); // Original unchanged
    });

    test('equality comparison works correctly', () {
      final notif1 = NotificationModel(
        id: 'notif-1',
        type: 'test',
        title: 'Title',
        message: 'Message',
        relatedEntityId: null,
        isRead: false,
        isActioned: false,
        createdAt: DateTime(2026, 9, 17),
      );

      final notif2 = NotificationModel(
        id: 'notif-1',
        type: 'test',
        title: 'Title',
        message: 'Message',
        relatedEntityId: null,
        isRead: false,
        isActioned: false,
        createdAt: DateTime(2026, 9, 17),
      );

      final notif3 = NotificationModel(
        id: 'notif-2',
        type: 'test',
        title: 'Title',
        message: 'Message',
        relatedEntityId: null,
        isRead: false,
        isActioned: false,
        createdAt: DateTime(2026, 9, 17),
      );

      expect(notif1, notif2);
      expect(notif1, isNot(notif3));
    });

    test('toJson serializes all fields correctly', () {
      final notification = NotificationModel(
        id: 'notif-1',
        type: 'team_invitation',
        title: 'Title',
        message: 'Message',
        relatedEntityId: 'entity-1',
        isRead: true,
        isActioned: false,
        createdAt: DateTime(2026, 9, 17, 10, 30),
        readAt: DateTime(2026, 9, 17, 11, 0),
        actionedAt: null,
      );

      final json = notification.toJson();

      expect(json['id'], 'notif-1');
      expect(json['type'], 'team_invitation');
      expect(json['title'], 'Title');
      expect(json['is_read'], true);
      expect(json['is_actioned'], false);
      expect(json['related_entity_id'], 'entity-1');
    });
  });
}
