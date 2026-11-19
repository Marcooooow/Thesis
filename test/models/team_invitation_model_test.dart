import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/models/team_models.dart';

void main() {
  group('TeamInvitation', () {
    test('fromJson creates TeamInvitation correctly', () {
      final json = {
        'id': 'inv-123',
        'team_id': 'team-456',
        'email': 'employee@example.com',
        'invited_by': 'manager@example.com',
        'role': 'employee',
        'status': 'pending',
        'created_at': '2026-09-17T10:00:00Z',
        'expires_at': '2026-09-24T10:00:00Z',
        'accepted_at': null,
        'declined_at': null,
      };

      final invitation = TeamInvitation.fromJson(json);

      expect(invitation.id, 'inv-123');
      expect(invitation.teamId, 'team-456');
      expect(invitation.email, 'employee@example.com');
      expect(invitation.invitedBy, 'manager@example.com');
      expect(invitation.role, 'employee');
      expect(invitation.status, 'pending');
      expect(invitation.acceptedAt, null);
      expect(invitation.declinedAt, null);
      expect(invitation.expiresAt, isNotNull);
    });

    test('isPending returns true for pending status', () {
      final invitation = TeamInvitation(
        id: 'inv-123',
        teamId: 'team-456',
        email: 'employee@example.com',
        invitedBy: 'manager@example.com',
        role: 'employee',
        status: 'pending',
        createdAt: DateTime.now(),
      );

      expect(invitation.isPending, true);
      expect(invitation.isAccepted, false);
      expect(invitation.isDeclined, false);
    });

    test('isAccepted returns true for accepted status', () {
      final invitation = TeamInvitation(
        id: 'inv-123',
        teamId: 'team-456',
        email: 'employee@example.com',
        invitedBy: 'manager@example.com',
        role: 'employee',
        status: 'accepted',
        createdAt: DateTime.now(),
        acceptedAt: DateTime.now(),
      );

      expect(invitation.isPending, false);
      expect(invitation.isAccepted, true);
      expect(invitation.isDeclined, false);
    });

    test('isDeclined returns true for declined status', () {
      final invitation = TeamInvitation(
        id: 'inv-123',
        teamId: 'team-456',
        email: 'employee@example.com',
        invitedBy: 'manager@example.com',
        role: 'employee',
        status: 'declined',
        createdAt: DateTime.now(),
        declinedAt: DateTime.now(),
      );

      expect(invitation.isPending, false);
      expect(invitation.isAccepted, false);
      expect(invitation.isDeclined, true);
    });

    test('toJson serializes correctly', () {
      final now = DateTime.now();
      final invitation = TeamInvitation(
        id: 'inv-123',
        teamId: 'team-456',
        email: 'employee@example.com',
        invitedBy: 'manager@example.com',
        role: 'employee',
        status: 'pending',
        createdAt: now,
      );

      final json = invitation.toJson();

      expect(json['id'], 'inv-123');
      expect(json['team_id'], 'team-456');
      expect(json['email'], 'employee@example.com');
      expect(json['role'], 'employee');
      expect(json['status'], 'pending');
    });

    test('equality based on id', () {
      final inv1 = TeamInvitation(
        id: 'inv-123',
        teamId: 'team-456',
        email: 'a@example.com',
        invitedBy: 'manager@example.com',
        role: 'employee',
        status: 'pending',
        createdAt: DateTime.now(),
      );

      final inv2 = TeamInvitation(
        id: 'inv-123',
        teamId: 'team-999',
        email: 'b@example.com',
        invitedBy: 'manager@example.com',
        role: 'employee',
        status: 'pending',
        createdAt: DateTime.now(),
      );

      expect(inv1, inv2);
    });
  });
}
