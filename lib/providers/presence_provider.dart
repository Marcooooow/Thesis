import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/dashboard/services/presence_service.dart';

/// Provider that manages user presence state and sends periodic heartbeats.
class PresenceProvider extends ChangeNotifier {
  PresenceProvider() {
    _loadToken(); // Load token from shared preferences
    // Heartbeat timer starts after authentication via initialize()
  }

  /// Initialize the provider after authentication is confirmed.
  /// Called by AuthGate once the user is verified.
  void initialize() {
    _startHeartbeatTimer(); // Start heartbeat timer for presence updates
  }

  // Internal state
  String? _token;
  Timer? _heartbeatTimer;
  final PresenceService _presenceService = PresenceService();

  // Current user's presence status
  bool _isOnline = false;
  DateTime? _lastHeartbeat;
  DateTime? _updatedAt;

  bool get isOnline => _isOnline;
  DateTime? get lastHeartbeat => _lastHeartbeat;
  DateTime? get updatedAt => _updatedAt;

  /// Loads the JWT token from shared preferences.
  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('jwt_token');

    if (_token == null) {
      // No token -> authentication required
      _isOnline = false;
      notifyListeners();
    } else {
      // If we have a token, send an initial heartbeat to set presence
      _sendHeartbeat();
    }
  }

  /// Start the heartbeat timer to send periodic heartbeats.
  void _startHeartbeatTimer() {
    // Send heartbeat every 25 seconds to stay well within the 30 second expiry
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (_token != null) {
        _sendHeartbeat();
      }
    });
  }

  /// Stop the heartbeat timer.
  void _stopHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Sends a heartbeat to the backend to maintain online status.
  Future<void> _sendHeartbeat() async {
    if (_token == null) return;

    try {
      final presence = await _presenceService.sendHeartbeat(_token!);
      _isOnline = presence['is_online'] as bool;
      _lastHeartbeat = DateTime.parse(presence['last_heartbeat']);
      _updatedAt = DateTime.parse(presence['updated_at']);
      notifyListeners();
    } catch (e) {
      // If the error is due to an invalid token, clear it.
      if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
        await _clearToken();
      }
      // Optionally log the error
      debugPrint('Failed to send presence heartbeat: $e');
    }
  }

  /// Clears the JWT token from shared preferences.
  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    _token = null;
    _isOnline = false;
    _lastHeartbeat = null;
    _updatedAt = null;
    _stopHeartbeatTimer();
    notifyListeners();
  }

  /// Retrieve the presence status of a specific user.
  Future<Map<String, dynamic>?> getUserPresence(String userId) async {
    if (_token == null) return null;
    return await _presenceService.getUserPresence(_token!, userId);
  }

  /// Bulk retrieve presence for multiple users.
  Future<List<Map<String, dynamic>>> getBulkPresence(List<String> userIds) async {
    if (_token == null || userIds.isEmpty) return [];
    return await _presenceService.getBulkPresence(_token!, userIds);
  }

  /// Called when the user logs out or the token is invalidated.
  Future<void> logout() async {
    await _clearToken();
  }

  @override
  void dispose() {
    _stopHeartbeatTimer();
    super.dispose();
  }
}