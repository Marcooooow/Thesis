import 'package:flutter/foundation.dart';

import '../../auth/services/api_service.dart';

class WorkService {
  final ApiService _apiService = ApiService();

  /// Start a new work session
  Future<Map<String, dynamic>> startWorkSession(String token) async {
    debugPrint('[SESSION] POST /work/session/start BEGIN');
    final response = await _apiService.postWithAuth(
      '/work/session/start',
      token,
      {},
    );
    debugPrint('[SESSION] startWorkSession completed');
    debugPrint('[SESSION] returnedSessionId=${response['id']}');
    return response;
  }

  /// End the current work session
  Future<Map<String, dynamic>> endWorkSession(String token) async {
    final response = await _apiService.postWithAuth(
      '/work/session/end',
      token,
      {},
    );
    return response;
  }

  /// Start a break
  Future<Map<String, dynamic>> startBreak(
    String token,
    String breakType, {
    String? recommendationId,
  }) async {
    final body = <String, dynamic>{'break_type': breakType};
    if (recommendationId != null && recommendationId.isNotEmpty) {
      body['recommendation_id'] = recommendationId;
    }
    final response = await _apiService.postWithAuth(
      '/work/break/start',
      token,
      body,
    );
    return response;
  }

  /// End a break by ID
  Future<Map<String, dynamic>> endBreak(String token, String breakId) async {
    final response = await _apiService.postWithAuth(
      '/work/break/end/$breakId',
      token,
      {},
    );
    return response;
  }

  /// Extend an active break
  Future<Map<String, dynamic>> extendBreak(
    String token,
    String breakId, {
    int extensionMinutes = 15,
    String? reason,
  }) async {
    final body = <String, dynamic>{
      'extension_minutes': extensionMinutes,
    };
    if (reason != null && reason.isNotEmpty) {
      body['reason'] = reason;
    }
    final response = await _apiService.postWithAuth(
      '/work/break/extend/$breakId',
      token,
      body,
    );
    return response;
  }

  /// Get the currently active break from the active session's break list.
  /// Avoids polling /work/break/active, which logs a 404 when no break is active.
  Future<Map<String, dynamic>?> getActiveBreak(String token) async {
    final breaks = await getActiveSessionBreaks(token);
    for (final breakItem in breaks) {
      if (breakItem is Map<String, dynamic> && breakItem['ended_at'] == null) {
        return breakItem;
      }
    }
    return null;
  }

  /// Get the current active work session (null if none).
  /// /work/session/active uses 404 to mean "no active session"; we opt into
  /// [allowNotFound] so shift detection can treat absence as a normal state.
  Future<Map<String, dynamic>?> getActiveSession(String token) async {
    final response = await _apiService.getMapWithAuth(
      '/work/session/active',
      token,
      allowNotFound: true,
    );
    return response;
  }

  /// Create a new task
  Future<Map<String, dynamic>> createTask(
    String token,
    Map<String, dynamic> taskData,
  ) async {
    final response = await _apiService.postWithAuth(
      '/work/tasks',
      token,
      taskData,
    );
    return response;
  }

  /// Get tasks for the active work session
  Future<List<dynamic>> getActiveSessionTasks(String token) async {
    // GET /work/tasks/active returns 404 when no active session; treat that as
    // an empty list so the UI can render its empty state without an error.
    final response = await _apiService.getListWithAuth(
      '/work/tasks/active',
      token,
      allowNotFound: true,
    );
    return response;
  }

  /// Start or end meeting as a Task (reuse existing task API; no new endpoints)
  Future<Map<String, dynamic>> createMeetingTask(String token, String sessionId, {String title = 'Meeting'}) async {
    return createTask(token, {
      'title': title,
      'category': 'Meeting',
      'work_session_id': sessionId,
    });
  }

  /// End meeting by completing the task (sets ended_at via backend status lifecycle)
  Future<Map<String, dynamic>> completeMeetingTask(String token, String taskId) async {
    return completeTask(token, taskId);
  }

  /// Update the status of a task
  Future<Map<String, dynamic>> updateTaskStatus(
    String token,
    String taskId,
    String status,
  ) async {
    final response = await _apiService.patchWithAuth(
      '/work/tasks/$taskId',
      token,
      {'status': status},
    );
    return response;
  }

  /// Transition a task from TODO to IN_PROGRESS
  /// Backend sets started_at = now()
  Future<Map<String, dynamic>> startTask(
    String token,
    String taskId,
  ) async {
    return updateTaskStatus(token, taskId, 'IN_PROGRESS');
  }

  /// Transition a task from IN_PROGRESS to DONE
  /// Backend sets ended_at = now() and computes actual_minutes
  Future<Map<String, dynamic>> completeTask(
    String token,
    String taskId,
  ) async {
    return updateTaskStatus(token, taskId, 'DONE');
  }

  /// Get breaks for the active work session
  Future<List<dynamic>> getActiveSessionBreaks(String token) async {
    // First get the active session to get its ID
    final sessionResponse = await _apiService.getMapWithAuth(
      '/work/session/active',
      token,
      allowNotFound: true,
    );

    if (sessionResponse == null) {
      // No active session
      return [];
    }

    final sessionId = sessionResponse['id'].toString();

    // Get breaks for this session
    final response = await _apiService.getListWithAuth(
      '/work/session/$sessionId/breaks',
      token,
    );
    return response;
  }

  /// Get breaks for a specific work session by ID
  Future<List<dynamic>> getSessionBreaks(String token, String sessionId) async {
    final response = await _apiService.getListWithAuth(
      '/work/session/$sessionId/breaks',
      token,
    );
    return response;
  }

  /// Get recommendations for a specific work session by ID
  /// Returns the full response object containing session_id + items list.
  Future<Map<String, dynamic>> getSessionRecommendations(String token, String sessionId) async {
    return await _apiService.getMapWithAuth(
      '/work/sessions/$sessionId/recommendations',
      token,
      allowNotFound: true,
    ) ?? {};
  }

  /// Get completed work sessions history
  Future<List<dynamic>> getSessionsHistory(String token) async {
    final response = await _apiService.getListWithAuth(
      '/work/sessions/history',
      token,
    );
    return response;
  }

  /// Get all tasks history for the current user
  Future<List<dynamic>> getTasksHistory(String token) async {
    final response = await _apiService.getListWithAuth(
      '/work/tasks/history',
      token,
    );
    return response;
  }

  /// Get team tasks for manager
  Future<List<dynamic>> getManagerTeamTasks(String token) async {
    return await _apiService.getListWithAuth('/work/manager/tasks', token);
  }

  /// Assign work task as manager
  Future<Map<String, dynamic>> assignManagerTask(String token, Map<String, dynamic> data) async {
    return await _apiService.postWithAuth('/work/manager/tasks', token, data);
  }

  /// Update manager task
  Future<Map<String, dynamic>> updateManagerTask(String token, String taskId, Map<String, dynamic> data) async {
    return await _apiService.patchWithAuth('/work/manager/tasks/$taskId', token, data);
  }

  /// Remove manager task assignment
  Future<Map<String, dynamic>> removeManagerTask(String token, String taskId) async {
    final res = await _apiService.deleteWithAuth('/work/manager/tasks/$taskId', token);
    return res ?? {'message': 'Deleted'};
  }

  /// Get active task categories
  Future<List<dynamic>> getTaskCategories(String token) async {
    return await _apiService.getListWithAuth('/work/categories', token);
  }
}
