import 'package:flutter/foundation.dart';
import 'package:intellibreak/features/dashboard/models/profile_model.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/dashboard/services/profile_image_service.dart';

class ProfileProvider extends ChangeNotifier {
  Profile? _profile;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  final ProfileImageService _profileImageService = ProfileImageService();

  Profile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;

  // New getter for profile image URL
  String? get profileImageUrl => _profile?.profileImageUrl;

  Future<void> loadProfile() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final apiService = ApiService();
      final token = await apiService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }
      final profile = await apiService.getProfile(token);
      _profile = profile;
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) {
        print('ProfileProvider error: $_error');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateProfile(Map<String, dynamic> updateData) async {
    if (_profile == null) {
      throw Exception('Profile not loaded');
    }

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final apiService = ApiService();
      final token = await apiService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }
      final updatedProfile = await apiService.updateProfile(token, updateData);
      _profile = updatedProfile;
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) {
        print('ProfileProvider error: $_error');
      }
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void clear() {
    _profile = null;
    _isLoading = false;
    _isSaving = false;
    _error = null;
    notifyListeners();
  }
}