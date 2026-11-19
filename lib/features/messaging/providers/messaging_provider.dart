import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/messaging/services/messaging_service.dart';

class MessagingProvider extends ChangeNotifier {
  List<dynamic> _conversations = [];
  bool _isLoading = false;
  String? _error;
  String? _currentUserId;
  Timer? _pollTimer;

  List<dynamic> get conversations => _conversations;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get currentUserId => _currentUserId;

  MessagingProvider() {
    startPolling();
  }

  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      loadConversations(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> loadConversations({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final token = await ApiService().getToken();
      if (token == null) {
        _error = 'Not authenticated';
        if (!silent) _isLoading = false;
        notifyListeners();
        return;
      }
      try {
        final me = await ApiService().getMe(token);
        _currentUserId = me['id']?.toString();
      } catch (_) {}

      final data = await MessagingService.getConversations(token);
      _conversations = data['conversations'] ?? [];
      _error = null;
    } catch (e) {
      if (!silent) {
        _error = e.toString();
      }
    } finally {
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }
}
