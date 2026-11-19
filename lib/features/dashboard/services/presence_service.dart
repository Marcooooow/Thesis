import 'package:flutter/foundation.dart';
import '../../auth/services/api_service.dart';

/// Service to handle backend communication for user presence tracking.
class PresenceService {
  final ApiService _apiService = ApiService();

  /// Send a heartbeat to the backend to maintain online status.
  /// Returns the current presence state of the authenticated user.
  Future<Map<String, dynamic>> sendHeartbeat(String token) async {
    return await _apiService.postWithAuth(
      '/presence/heartbeat',
      token,
      {},
    );
  }

  /// Retrieve the presence status of a specific user.
  /// returns null if the user has no presence record.
  Future<Map<String, dynamic>?> getUserPresence(String token, String userId) async {
    return await _apiService.getMapWithAuth(
      '/presence/status/$userId',
      token,
      allowNotFound: true,
    );
  }

  /// Bulk retrieve presence for multiple users (e.g. for team lists).
  Future<List<Map<String, dynamic>>> getBulkPresence(String token, List<String> userIds) async {
    if (userIds.isEmpty) return [];
    final queryParams = userIds.map((id) => 'user_ids=$id').join('&');
    try {
      final result = await _apiService.getListWithAuth(
        '/presence/status?$queryParams',
        token,
        allowNotFound: true,
      );
      return result.cast<Map<String, dynamic>>();
    } catch (_) {
      // Fallback to individual fetches if bulk query fails
      final List<Map<String, dynamic>> results = [];
      for (final userId in userIds) {
        final presence = await getUserPresence(token, userId);
        if (presence != null) {
          results.add(presence);
        }
      }
      return results;
    }
  }
}
