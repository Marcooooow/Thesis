import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/notifications/models/notification_model.dart';
import '../features/notifications/services/notification_service.dart';

/// Provider that manages the notification state.
/// Fetches and maintains the list of notifications for the authenticated user.
/// Handles marking notifications as read and clearing state.
class NotificationProvider extends ChangeNotifier {
  NotificationProvider() {
    _loadToken();
  }

  // Internal state
  List<NotificationModel> _notifications = [];
  bool _isLoading = false;
  String? _error;
  final NotificationService _notificationService = NotificationService();

  // Getters
  List<NotificationModel> get notifications => _notifications;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Loads the JWT token from shared preferences
  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.getString('jwt_token');
  }

  /// Loads notifications from the backend
  Future<void> loadNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    if (token == null) {
      debugPrint('[NOTIF_PROVIDER] No JWT token');
      _updateState(
        notifications: [],
        isLoading: false,
        error: 'Not authenticated',
      );
      return;
    }

    debugPrint('[NOTIF_PROVIDER] Loading notifications with token');
    _updateState(
      notifications: _notifications,
      isLoading: true,
      error: null,
    );

    try {
      debugPrint('[NOTIF_PROVIDER] Calling fetchNotifications');
      final notifications = await _notificationService.fetchNotifications(token);
      debugPrint('[NOTIF_PROVIDER] Got ${notifications.length} notifications');
      _updateState(
        notifications: notifications,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      debugPrint('[NOTIF_PROVIDER] Error loading notifications: $e');
      _updateState(
        notifications: _notifications,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Refreshes the notification list (same as loadNotifications)
  Future<void> refresh() async {
    await loadNotifications();
  }

  /// Marks a single notification as read
  Future<void> markAsRead(String notificationId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    if (token == null) {
      _updateState(
        notifications: _notifications,
        isLoading: false,
        error: 'Not authenticated',
      );
      return;
    }

    try {
      final updated = await _notificationService.markNotificationAsRead(
        token,
        notificationId,
      );

      // Update the local notification with the response
      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1) {
        _notifications[index] = updated;
        notifyListeners();
      }
    } catch (e) {
      _updateState(
        notifications: _notifications,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Marks all notifications as read
  Future<void> markAllAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    if (token == null) {
      _updateState(
        notifications: _notifications,
        isLoading: false,
        error: 'Not authenticated',
      );
      return;
    }

    try {
      await _notificationService.markAllNotificationsAsRead(token);
      _notifications = _notifications.map((n) => n.copyWith(isRead: true, readAt: DateTime.now())).toList();
      notifyListeners();
    } catch (e) {
      _updateState(
        notifications: _notifications,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Clears all notifications and state
  void clear() {
    _updateState(
      notifications: [],
      isLoading: false,
      error: null,
    );
  }

  /// Internal method to update state and notify listeners
  void _updateState({
    required List<NotificationModel> notifications,
    required bool isLoading,
    required String? error,
  }) {
    _notifications = notifications;
    _isLoading = isLoading;
    _error = error;
    notifyListeners();
  }

  /// Test helper to manually set notifications for testing unreadCount
  void testSetNotifications(List<NotificationModel> notifications) {
    _notifications = notifications;
    notifyListeners();
  }

  /// Test helper to set loading state
  void testSetLoadingState(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Test helper to set error state
  void testSetError(String error) {
    _error = error;
    notifyListeners();
  }
}
