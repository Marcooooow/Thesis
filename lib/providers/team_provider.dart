import 'package:flutter/foundation.dart';
import 'package:intellibreak/models/team_models.dart';
import 'package:intellibreak/features/team/team_service.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';

/// Represents a group within a team.
class TeamGroup {
  final String id;
  final String name;
  final String teamId;

  TeamGroup({
    required this.id,
    required this.name,
    required this.teamId,
  });

  factory TeamGroup.fromJson(Map<String, dynamic> json) {
    return TeamGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      teamId: json['team_id'] as String,
    );
  }
}

/// Manages team state and operations for the authenticated user.
class TeamProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final TeamService _teamService = TeamService();

  Team? _currentTeam;
  List<TeamMember> _teamMembers = [];
  List<TeamInvitation> _invitations = [];
  List<TeamGroup> _groups = [];
  bool _isLoading = false;
  bool _invitationsLoading = false;
  bool _groupsLoading = false;
  String? _error;
  String? _invitationsError;
  String? _groupsError;
  String? _currentUserId;

  Team? get currentTeam => _currentTeam;
  List<TeamMember> get teamMembers => _teamMembers;
  List<TeamInvitation> get invitations => _invitations;
  List<TeamGroup> get groups => _groups;
  bool get isLoading => _isLoading;
  bool get invitationsLoading => _invitationsLoading;
  bool get groupsLoading => _groupsLoading;
  String? get error => _error;
  String? get invitationsError => _invitationsError;
  String? get groupsError => _groupsError;

  /// Whether the current user has a team.
  bool get hasTeam => _currentTeam != null;

  /// Whether the current user is the team manager.
  /// Used to determine if manager-only controls should be shown.
  bool get isTeamManager {
    if (_currentTeam == null || _currentUserId == null) return false;
    return _currentUserId == _currentTeam?.managerId;
  }

  /// Temporary getter for diagnostics: expose current user ID.
  String? get currentUserId => _currentUserId;

  /// Set the current user's ID for role checking.
  void setCurrentUserId(String userId) {
    _currentUserId = userId;
    notifyListeners();
  }

  /// Load the current user's team information.
  /// Returns the team if the user has one, or null if they're working solo.
  Future<Team?> loadMyTeam(String token) async {
    _setLoading(true);
    _error = null;

    try {
      // Get the user's team (single object or null)
      final response = await _teamService.getMyTeam(token);

      // If no team, user is solo
      if (response == null) {
        _currentTeam = null;
        notifyListeners();
        return null;
      }

      _currentTeam = Team.fromJson(response);

      notifyListeners();
      return _currentTeam;
    } catch (e) {
      _error = 'Failed to load team: $e';
      _currentTeam = null;
      notifyListeners();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Load team members for the current team with activity status.
  Future<void> loadTeamMembers(String teamId, String token) async {
    _setLoading(true);
    _error = null;

    try {
      final response = await _teamService.getMyTeamView(token);
      _teamMembers = response
          .where((item) => item != null)
          .cast<Map<String, dynamic>>()
          .map((item) => TeamMember.fromJson(item))
          .toList();

      notifyListeners();
    } catch (e) {
      try {
        final fallbackResponse = await _teamService.getTeamMembers(teamId, token);
        _teamMembers = fallbackResponse
            .where((item) => item != null)
            .cast<Map<String, dynamic>>()
            .map((item) => TeamMember.fromJson(item))
            .toList();
        notifyListeners();
      } catch (fallbackE) {
        _error = 'Failed to load team members: $e';
        _teamMembers = [];
        notifyListeners();
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Load groups for the current team.
  Future<void> loadGroups(String teamId, String token) async {
    _groupsLoading = true;
    _groupsError = null;
    notifyListeners();

    try {
      final response = await _teamService.getGroups(teamId, token);
      _groups = response
          .map((item) => TeamGroup.fromJson(item))
          .toList();
      notifyListeners();
    } catch (e) {
      _groupsError = 'Failed to load groups: $e';
      _groups = [];
      notifyListeners();
    } finally {
      _groupsLoading = false;
      notifyListeners();
    }
  }

  /// Load pending invitations for the current team.
  Future<void> loadInvitations(String teamId, String token) async {
    _invitationsLoading = true;
    _invitationsError = null;
    notifyListeners();

    try {
      _invitations = await _teamService.getInvitations(teamId, token);
      notifyListeners();
    } catch (e) {
      _invitationsError = 'Failed to load invitations: $e';
      _invitations = [];
      notifyListeners();
    } finally {
      _invitationsLoading = false;
      notifyListeners();
    }
  }

  /// Create a new team.
  /// The current user will become the team manager.
  Future<Team?> createTeam(
    String token,
    String name, {
    String? description,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      final response = await _apiService.postWithAuth(
        '/teams',
        token,
        {
          'name': name,
          if (description != null && description.isNotEmpty) 'description': description,
        },
      );

      _currentTeam = Team.fromJson(response);
      notifyListeners();
      return _currentTeam;
    } catch (e) {
      _error = 'Failed to create team: $e';
      notifyListeners();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Send an invitation to an employee.
  Future<bool> sendInvitation(
    String token,
    String teamId,
    String email,
  ) async {
    _error = null;

    try {
      await _teamService.sendInvitation(token, teamId, email);
      // Refresh invitations after sending
      await loadInvitations(teamId, token);
      return true;
    } catch (e) {
      _error = 'Failed to send invitation: $e';
      notifyListeners();
      return false;
    }
  }

  /// Remove a member from the team.
  Future<bool> removeMember(
    String token,
    String teamId,
    String memberId,
  ) async {
    _error = null;

    try {
      await _teamService.removeMember(token, teamId, memberId);
      // Refresh team members
      await loadTeamMembers(teamId, token);
      return true;
    } catch (e) {
      _error = 'Failed to remove member: $e';
      notifyListeners();
      return false;
    }
  }

  /// Move a member to a group.
  Future<bool> moveToGroup(
    String token,
    String teamId,
    String memberId,
    String groupId,
  ) async {
    _error = null;

    try {
      await _teamService.moveToGroup(token, teamId, memberId, groupId);
      // Refresh team members
      await loadTeamMembers(teamId, token);
      return true;
    } catch (e) {
      _error = 'Failed to move member: $e';
      notifyListeners();
      return false;
    }
  }

  /// Create a new group.
  Future<bool> createGroup(
    String token,
    String teamId,
    String name,
  ) async {
    _groupsError = null;

    try {
      await _teamService.createGroup(token, teamId, name);
      // Refresh groups
      await loadGroups(teamId, token);
      return true;
    } catch (e) {
      _groupsError = 'Failed to create group: $e';
      notifyListeners();
      return false;
    }
  }

  /// Accept a team invitation.
  Future<bool> acceptInvitation(
    String invitationId,
    String token,
  ) async {
    _error = null;

    try {
      await _teamService.acceptInvitation(invitationId, token);

      // Refresh team and members after accepting
      if (_currentTeam != null) {
        await Future.wait([
          loadMyTeam(token),
          loadTeamMembers(_currentTeam!.id, token),
          loadInvitations(_currentTeam!.id, token),
        ]);
      }
      return true;
    } catch (e) {
      _error = 'Failed to accept invitation: $e';
      notifyListeners();
      return false;
    }
  }

  /// Decline a team invitation.
  Future<bool> declineInvitation(
    String invitationId,
    String token,
    String teamId,
  ) async {
    _error = null;

    try {
      await _teamService.declineInvitation(invitationId, token);

      // Refresh invitations after declining
      await loadInvitations(teamId, token);
      return true;
    } catch (e) {
      _error = 'Failed to decline invitation: $e';
      notifyListeners();
      return false;
    }
  }

  /// Refresh the current team and all related data.
  Future<void> refresh(String token) async {
    if (_currentTeam == null) {
      await loadMyTeam(token);
    } else {
      final futures = <Future<void>>[
        loadMyTeam(token),
        loadTeamMembers(_currentTeam!.id, token),
        loadGroups(_currentTeam!.id, token),
      ];
      if (isTeamManager) {
        futures.add(loadInvitations(_currentTeam!.id, token));
      }
      await Future.wait(futures);
    }
  }

  /// Clear team state (e.g., on logout).
  void clear() {
    _currentTeam = null;
    _teamMembers = [];
    _invitations = [];
    _groups = [];
    _error = null;
    _invitationsError = null;
    _groupsError = null;
    _isLoading = false;
    _invitationsLoading = false;
    _groupsLoading = false;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
