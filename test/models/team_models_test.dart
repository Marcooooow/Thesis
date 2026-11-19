import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/models/team_models.dart';

void main() {
  group('Team Models', () {
    test('Team.fromJson creates Team correctly', () {
      final json = {
        'id': 'team-123',
        'name': 'Engineering',
        'description': 'Engineering team',
        'manager_id': 'user-1',
        'manager_name': 'Alice',
        'member_count': 5,
        'is_active': true,
        'created_at': '2026-01-15T10:00:00Z',
        'updated_at': '2026-09-17T10:00:00Z',
      };

      final team = Team.fromJson(json);

      expect(team.id, 'team-123');
      expect(team.name, 'Engineering');
      expect(team.description, 'Engineering team');
      expect(team.managerId, 'user-1');
      expect(team.managerName, 'Alice');
      expect(team.memberCount, 5);
      expect(team.isActive, true);
    });

    test('Team.toJson converts Team to JSON correctly', () {
      final team = Team(
        id: 'team-123',
        name: 'Engineering',
        description: 'Engineering team',
        managerId: 'user-1',
        managerName: 'Alice',
        memberCount: 5,
        isActive: true,
        createdAt: DateTime(2026, 1, 15),
        updatedAt: DateTime(2026, 9, 17),
      );

      final json = team.toJson();

      expect(json['id'], 'team-123');
      expect(json['name'], 'Engineering');
      expect(json['description'], 'Engineering team');
      expect(json['manager_id'], 'user-1');
      expect(json['manager_name'], 'Alice');
      expect(json['member_count'], 5);
      expect(json['is_active'], true);
    });

    test('TeamMember.fromJson creates TeamMember correctly', () {
      final json = {
        'id': 'user-123',
        'profile_id': 'profile-123',
        'full_name': 'Bob',
        'email': 'bob@example.com',
        'role': 'EMPLOYEE',
        'joined_at': '2026-08-15T10:00:00Z',
        'is_current': true,
      };

      final member = TeamMember.fromJson(json);

      expect(member.userId, 'user-123');
      expect(member.profileId, 'profile-123');
      expect(member.userName, 'Bob');
      expect(member.userEmail, 'bob@example.com');
      expect(member.role, 'EMPLOYEE');
      expect(member.isCurrent, true);
    });
  });
}
