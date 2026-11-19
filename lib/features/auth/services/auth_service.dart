import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class AuthService {
  factory AuthService() => _instance;
  AuthService._internal() : _auth = FirebaseAuth.instance;
  static final AuthService _instance = AuthService._internal();

  final FirebaseAuth _auth;
  VoidCallback? _onTokenChanged;

  // Stream to listen to auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Set a callback to be invoked when the backend JWT token changes.
  void setTokenChangedCallback(VoidCallback? callback) {
    _onTokenChanged = callback;
  }

  /// Invoke the token changed callback if set.
  void _notifyTokenChanged() {
    if (_onTokenChanged != null) {
      _onTokenChanged!();
    }
  }

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Sign in with email and password
  Future<UserCredential> signIn(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Register with email and password
  Future<UserCredential> register(String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Sign out - clear both Firebase auth and backend JWT token
  Future<void> signOut() async {
    debugPrint('[DEMO_LOGOUT] AuthService.signOut called');
    try {
      // Clear the backend JWT token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt_token');
      await prefs.remove('refresh_token');
      // Notify listeners that the token has changed
      _notifyTokenChanged();

      // Sign out from Firebase
      debugPrint('[DEMO_LOGOUT] About to sign out from Firebase');
      await _auth.signOut();
      debugPrint('[DEMO_LOGOUT] Firebase signOut completed');
    } on FirebaseAuthException catch (e) {
      debugPrint('[DEMO_LOGOUT] Error during signOut: $e');
      throw _handleAuthException(e);
    } finally {
      debugPrint('[DEMO_LOGOUT] Sign out cleanup completed');
    }
    debugPrint('[DEMO_LOGOUT] AuthService.signOut finished');
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }


  // Handle Firebase Auth exceptions and convert to user-friendly messages
  Exception _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return Exception('The email address is not valid.');
      case 'user-disabled':
        return Exception('This user account has been disabled.');
      case 'user-not-found':
        return Exception('No user found with this email.');
      case 'wrong-password':
        return Exception('Wrong password provided for this user.');
      case 'too-many-requests':
        return Exception('Too many requests. Try again later.');
      case 'operation-not-allowed':
        return Exception('Operation not allowed. Contact support.');
      case 'weak-password':
        return Exception('Password is too weak.');
      case 'email-already-in-use':
        return Exception('An account already exists for this email.');
      case 'invalid-credential':
        return Exception('Invalid email or password.');
      default:
        return Exception('Authentication failed: ${e.message}');
    }
  }

  // Check if user is authenticated
  bool isAuthenticated() {
    return _auth.currentUser != null;
  }

  // Get user display name or email
  String getUserDisplayName() {
    final user = _auth.currentUser;
    if (user == null) return '';
    return user.displayName ?? user.email ?? 'User';
  }

  // Get user email
  String? getUserEmail() {
    return _auth.currentUser?.email;
  }

}