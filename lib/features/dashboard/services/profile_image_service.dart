import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class ProfileImageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Storage path for profile images
  static const String _storagePath = 'profile-images';

  // Maximum file size (5MB)
  static const int _maxFileSize = 5 * 1024 * 1024;

  // Supported image formats
  static const List<String> _supportedFormats = ['jpg', 'jpeg', 'png', 'webp'];

  /// Get the current user's Firebase UID
  String? getCurrentUid() {
    final user = _auth.currentUser;
    return user?.uid;
  }

  /// Check if user is authenticated
  bool isAuthenticated() {
    return _auth.currentUser != null;
  }

  /// Get the storage reference for a user's profile image
  Reference _getProfileImageReference(String uid) {
    return _storage.ref().child('$_storagePath/$uid/profile');
  }

  /// Validate image file
  Future<bool> validateImageFile(XFile file) async {
    // Check file size
    final fileSize = await file.length();
    if (fileSize > _maxFileSize) {
      return false;
    }

    // Check file extension
    final extension = file.name.split('.').last.toLowerCase();
    if (!_supportedFormats.contains(extension)) {
      return false;
    }

    return true;
  }

  /// Pick an image from gallery or camera
  Future<XFile?> pickImage({required ImageSource source}) async {
    if (!isAuthenticated()) {
      throw Exception('User not authenticated');
    }

    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    return image;
  }

  /// Upload profile image to Firebase Storage
  Future<String?> uploadProfileImage(XFile imageFile) async {
    if (!isAuthenticated()) {
      throw Exception('User not authenticated');
    }

    // Validate the image file
    final isValid = await validateImageFile(imageFile);
    if (!isValid) {
      throw Exception('Invalid image file. Please select a JPG, PNG, or WebP image under 5MB.');
    }

    final uid = getCurrentUid();
    if (uid == null) {
      throw Exception('Unable to get user ID');
    }

    try {
      // Get reference to the storage location
      final ref = _getProfileImageReference(uid);

      // Delete existing image if any
      await ref.delete().catchError((_) {}); // Ignore if no existing image

      // Upload the image
      final uploadTask = ref.putFile(
        File(imageFile.path),
        SettableMetadata(
          contentType: 'image/${imageFile.name.split('.').last}',
        ),
      );

      // Wait for upload to complete
      final snapshot = await uploadTask.whenComplete(() => null);

      // Get download URL
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      if (kDebugMode) {
        print('Error uploading profile image: $e');
      }
      throw Exception('Failed to upload profile image: $e');
    }
  }

  /// Delete profile image from Firebase Storage
  Future<bool> deleteProfileImage() async {
    if (!isAuthenticated()) {
      throw Exception('User not authenticated');
    }

    final uid = getCurrentUid();
    if (uid == null) {
      throw Exception('Unable to get user ID');
    }

    try {
      final ref = _getProfileImageReference(uid);
      await ref.delete();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting profile image: $e');
      }
      return false;
    }
  }

  /// Get download URL for user's profile image
  Future<String?> getProfileImageUrl() async {
    if (!isAuthenticated()) {
      return null;
    }

    final uid = getCurrentUid();
    if (uid == null) {
      return null;
    }

    try {
      final ref = _getProfileImageReference(uid);
      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      // Image doesn't exist or other error
      if (kDebugMode) {
        print('Error getting profile image URL: $e');
      }
      return null;
    }
  }
}