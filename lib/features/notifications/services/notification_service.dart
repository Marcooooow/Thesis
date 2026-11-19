import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/notifications/models/notification_model.dart';

class NotificationService {
  final ApiService _apiService = ApiService();

  /// Fetches all notifications for the authenticated user
  Future<List<NotificationModel>> fetchNotifications(String token) async {
    try {
      debugPrint('[NOTIF_HTTP] GET /notifications starting');
      final response = await _apiService.getMapWithAuth(
        '/notifications',
        token,
      );

      if (response == null) {
        debugPrint('[NOTIF_HTTP] Response is null');
        return [];
      }

      debugPrint('[NOTIF_HTTP] Status: 200 (assumed from success)');
      debugPrint('[NOTIF_HTTP] Response type: ${response.runtimeType}');

      // Extract the notifications array from the response object
      // response is guaranteed non-null at this point
      final notificationsData = response['notifications'];
      if (notificationsData is! List<dynamic>) {
        throw FormatException('notifications key is not a list: ${notificationsData.runtimeType}');
      }

      debugPrint('[NOTIF_HTTP] Response body has ${notificationsData.length} items');

      final notifications = notificationsData
          .cast<Map<String, dynamic>>()
          .map((json) {
            debugPrint('[NOTIF_PARSE] Parsing notification: $json');
            return NotificationModel.fromJson(json);
          })
          .toList();

      debugPrint('[NOTIF_SUCCESS] Parsed ${notifications.length} notifications');
      return notifications;
    } catch (e) {
      debugPrint('[NOTIF_ERROR] Exception: $e');
      debugPrint('[NOTIF_ERROR] Stack: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Marks a single notification as read
  Future<NotificationModel> markNotificationAsRead(
    String token,
    String notificationId,
  ) async {
    try {
      final response = await _apiService.patchWithAuth(
        '/notifications/$notificationId/read',
        token,
        {},
      );

      return NotificationModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  /// Marks all notifications as read
  Future<void> markAllNotificationsAsRead(String token) async {
    try {
      await _apiService.postWithAuth(
        '/notifications/read-all',
        token,
        {},
      );
    } catch (e) {
      rethrow;
    }
  }
}
