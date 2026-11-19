import 'package:intellibreak/models/team_models.dart';
import '../auth/services/api_service.dart';
import 'package:flutter/foundation.dart';

class TeamService {
  final ApiService _apiService = ApiService();

  /// Get the current user's team (works for both managers and employees).
  Future<Map<String, dynamic>?> getMyTeam(String token) async {
    final response = await _apiService.getMapWithAuth('/teams/me', token);
    return response;
  }

  /// Get team members for a specific team.
  Future<List<dynamic>> getTeamMembers(String teamId, String token) async {
    debugPrint('[TEAM_MEMBERS_HTTP] BEGIN /teams/$teamId/members');
    final response = await _apiService.getListWithAuth(
      '/teams/$teamId/members',
      token,
    );
    debugPrint('[TEAM_MEMBERS_HTTP] RESPONSE=$response');
    return response;
  }

  /// Get team view with active work sessions and breaks.
  Future<List<dynamic>> getMyTeamView(String token) async {
    final response = await _apiService.getListWithAuth(
      '/teams/my-team-view',
      token,
    );
    return response;
  }

  /// Get batched team activity summary.
  Future<List<dynamic>> getTeamActivitySummary(String teamId, String token) async {
    debugPrint('[TEAM_ACTIVITY_SUMMARY] BEGIN /teams/$teamId/activity-summary');
    final response = await _apiService.getListWithAuth(
      '/teams/$teamId/activity-summary',
      token,
    );
    return response;
  }

  /// Remove a member from the team.
  Future<Map<String, dynamic>> removeMember(
    String token,
    String teamId,
    String memberId,
  ) async {
    return await _apiService.deleteWithAuth(
      '/teams/$teamId/members/$memberId',
      token,
    ) ?? {};
  }

  /// Move a member to a group.
  Future<Map<String, dynamic>> moveToGroup(
    String token,
    String teamId,
    String memberId,
    String groupId,
  ) async {
    return await _apiService.postWithAuth(
      '/teams/$teamId/members/$memberId/move-to-group?group_id=$groupId',
      token,
      {},
    );
  }

  /// Create a new team.
  Future<Map<String, dynamic>> createTeam(
    String token,
    String name, {
    String? description,
  }) async {
    final body = {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
    };
    return await _apiService.postWithAuth('/teams', token, body);
  }

  /// Get a specific team by ID.
  Future<Map<String, dynamic>> getTeam(String teamId, String token) async {
    return await _apiService.getMapWithAuth('/teams/$teamId', token) ?? {};
  }

  /// Search users for team invitation by name or email.
  Future<List<Map<String, dynamic>>> searchUsersForInvitation(
    String teamId,
    String query,
    String token,
  ) async {
    final response = await _apiService.getListWithAuth(
      '/teams/$teamId/search-users?q=$query',
      token,
    );
    return response.cast<Map<String, dynamic>>();
  }

  /// Send an invitation to join a team.
  Future<Map<String, dynamic>> sendInvitation(
    String token,
    String teamId,
    String email, {
    String role = 'employee',
  }) async {
    final body = {
      'email': email,
      'role': role,
    };
    return await _apiService.postWithAuth(
      '/teams/$teamId/invitations',
      token,
      body,
    );
  }

  /// Get pending invitations for a team.
  Future<List<TeamInvitation>> getInvitations(String teamId, String token) async {
    final response = await _apiService.getListWithAuth(
      '/teams/$teamId/invitations',
      token,
    );
    return response
        .cast<Map<String, dynamic>>()
        .map((item) => TeamInvitation.fromJson(item))
        .toList();
  }

  /// Accept a team invitation.
  Future<Map<String, dynamic>> acceptInvitation(
    String invitationId,
    String token,
  ) async {
    return await _apiService.postWithAuth(
      '/teams/invitations/$invitationId/accept',
      token,
      {},
    );
  }

  /// Decline a team invitation.
  Future<Map<String, dynamic>> declineInvitation(
    String invitationId,
    String token,
  ) async {
    return await _apiService.postWithAuth(
      '/teams/invitations/$invitationId/decline',
      token,
      {},
    );
  }

  /// Get all groups in a team.
  Future<List<Map<String, dynamic>>> getGroups(String teamId, String token) async {
    final response = await _apiService.getListWithAuth(
      '/teams/$teamId/groups',
      token,
    );
    return response.cast<Map<String, dynamic>>();
  }

  /// Create a new group.
  Future<Map<String, dynamic>> createGroup(
    String token,
    String teamId,
    String name,
  ) async {
    return await _apiService.postWithAuth(
      '/teams/$teamId/groups?name=$name',
      token,
      {},
    );
  }
}
