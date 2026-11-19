import 'package:flutter_test/flutter_test.dart';
import 'package:intellibreak/providers/team_provider.dart';
import 'package:intellibreak/models/team_models.dart';

void main() {
  group('TeamProvider Invitations & Role Logic', () {
    late TeamProvider teamProvider;

    setUp(() {
      teamProvider = TeamProvider();
    });

    tearDown(() {
      teamProvider.clear();
    });

    test('invitations list starts empty', () {
      expect(teamProvider.invitations, isEmpty);
      expect(teamProvider.invitationsError, null);
      expect(teamProvider.invitationsLoading, false);
    });

    test('invitationsLoading flag starts false', () {
      expect(teamProvider.invitationsLoading, false);
    });

    test('clear() resets invitation state', () {
      teamProvider.clear();

      expect(teamProvider.invitations, isEmpty);
      expect(teamProvider.invitationsError, null);
      expect(teamProvider.invitationsLoading, false);
    });

    test('isTeamManager is false when user is employee or team is null', () {
      expect(teamProvider.isTeamManager, false);

      teamProvider.setCurrentUserId('user-1');
      // No team set
      expect(teamProvider.isTeamManager, false);
    });
  });
}

