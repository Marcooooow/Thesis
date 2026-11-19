import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/auth/widgets/auth_buttons.dart';
import 'package:intellibreak/features/auth/widgets/auth_card.dart';
import 'package:intellibreak/features/auth/widgets/auth_layout.dart';
import 'package:intellibreak/features/auth/widgets/auth_logo.dart';
import 'package:intellibreak/features/auth/widgets/auth_form_field.dart';
import 'package:intellibreak/features/auth/widgets/auth_header.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'login_screen.dart';
import 'totp_challenge_screen.dart';
import '../../../routes/auth_gate.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({Key? key}) : super(key: key);

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmNewPasswordController =
      TextEditingController();
  bool _isLoading = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmNewPassword = true;
  final ApiService _apiService = ApiService();

  // Reused registration password rules (backend COMMON_WEAK_PASSWORDS + min 12)
  static const _commonWeakPasswords = {
    'password', '12345678', 'qwerty', 'password123', 'admin123',
    '123456789', '11111111', 'passw0rd', 'password1234', 'qwerty123456',
    '12345678abcd',
  };

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    super.dispose();
  }

  // Helper to parse JWT token (without verification) to get claims
  Map<String, dynamic>? _parseJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = parts[1];
      final normalized = base64Url.decode(_normalizeBase64(payload));
      return jsonDecode(utf8.decode(normalized));
    } catch (e) {
      return null;
    }
  }

  String _normalizeBase64(String base64) {
    final padding = base64.length % 4;
    if (padding == 0) return base64;
    if (padding == 2) return base64 + '==';
    if (padding == 3) return base64 + '=';
    return base64 + '==='; // padding 1 (should be 3 chars total; rare but handle)
  }

  Future<void> _changePassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please correct the errors below.'),
          backgroundColor: DesignSystem.getSemanticColor(
            context,
            SemanticColor.error,
          ),
        ),
      );
      return;
    }
    setState(() {
      _isLoading = true;
    });
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      try {
        // Get the current token (restricted token) to extract email for re-login
        final currentToken = await _apiService.getToken();
        if (currentToken == null || currentToken.trim().isEmpty) {
          throw Exception('No authentication token found');
        }
        final trimmedToken = currentToken.trim();
        final payload = _parseJwt(trimmedToken);
        final email = payload?['sub']?.toString().trim();
        if (email == null) {
          throw Exception('Unable to extract user email from token');
        }

        // Call the change password endpoint
        await _apiService.changePassword(
          _currentPasswordController.text,
          _newPasswordController.text,
        );

        // After successful password change, log in again with the new password
        // to obtain a normal access token
        final loginData = await _apiService.login(email, _newPasswordController.text);

        if (loginData['requires_2fa']) {
          // Save the challenge token temporarily for 2FA verification
          final String challengeToken = loginData['access_token'];
          if (!mounted) return;
          navigator.push(
            MaterialPageRoute(
              builder: (_) => TotpChallengeScreen(challengeToken: challengeToken),
            ),
          );
        } else {
          // Login method already saved the token if not 2FA
          if (!mounted) return;
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthGate()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Failed to change password: $e'),
              backgroundColor: DesignSystem.getSemanticColor(
                context,
                SemanticColor.error,
              ),
            ),
          );
          // If the error is due to an invalid/expired token, send user back to login
          if (e.toString().contains('401') ||
              e.toString().contains('403') ||
              e.toString().contains('token')) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                navigator.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            });
          }
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: AuthLayout(
        desktop: _buildDesktopChangePassword(context),
        tablet: _buildTabletChangePassword(context),
        mobile: _buildMobileChangePassword(context),
      ),
    );
  }

  Widget _buildMobileChangePassword(BuildContext context) =>
      _buildFullPageChangePassword(context, maxWidth: 400);

  Widget _buildTabletChangePassword(BuildContext context) =>
      _buildFullPageChangePassword(context, maxWidth: 400);

  Widget _buildDesktopChangePassword(BuildContext context) =>
      _buildFullPageChangePassword(context, maxWidth: 400);

  Widget _buildFullPageChangePassword(BuildContext context, {double maxWidth = 400}) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
        children: [
          // Theme toggle (top-right)
          Positioned(
            top: 24,
            right: 24,
            child: IconButton(
              onPressed: () {
                final themeController = Provider.of<ThemeController>(
                  context,
                  listen: false,
                );
                themeController.setThemeMode(
                  themeController.themeMode == ThemeMode.light
                      ? ThemeMode.dark
                      : ThemeMode.light,
                );
              },
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.sunny
                    : Icons.nightlight_round,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ),
              ),
            ),
          ),
          // Main content centered on full screen
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: AuthCard(child: _buildChangePasswordForm(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangePasswordForm(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthLogo(),
        SizedBox(height: DesignSystem.spacingL),
        const AuthHeader(
          title: 'Change Password',
          subtitle: 'Your password must be changed before continuing',
        ),
        SizedBox(height: DesignSystem.spacingXL),
        AuthFormField(
          label: 'Current Password',
          hintText: 'Enter your current password',
          controller: _currentPasswordController,
          prefixIcon: Icons.lock_outline_rounded,
          obscureText: _obscureCurrentPassword,
          suffixIcon: IconButton(
            onPressed: () {
              setState(() {
                _obscureCurrentPassword = !_obscureCurrentPassword;
              });
            },
            icon: Icon(
              _obscureCurrentPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurfaceVariant,
              ),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your current password';
            }
            return null;
          },
        ),
        SizedBox(height: DesignSystem.spacingL),
        AuthFormField(
          label: 'New Password',
          hintText: 'Enter new password',
          controller: _newPasswordController,
          prefixIcon: Icons.lock_outline_rounded,
          obscureText: _obscureNewPassword,
          suffixIcon: IconButton(
            onPressed: () {
              setState(() {
                _obscureNewPassword = !_obscureNewPassword;
              });
            },
            icon: Icon(
              _obscureNewPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurfaceVariant,
              ),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a new password';
            }
            if (value.length < 12) {
              return 'Password must be at least 12 characters long';
            }
            if (value.toLowerCase() == 'password' ||
                value.toLowerCase() == 'password123' ||
                value == '12345678' ||
                value.toLowerCase() == 'qwerty') {
              return 'This password is too common. Please choose a stronger password.';
            }
            return null;
          },
        ),
        SizedBox(height: DesignSystem.spacingL),
        AuthFormField(
          label: 'Confirm New Password',
          hintText: 'Confirm new password',
          controller: _confirmNewPasswordController,
          prefixIcon: Icons.lock_outline_rounded,
          obscureText: _obscureConfirmNewPassword,
          suffixIcon: IconButton(
            onPressed: () {
              setState(() {
                _obscureConfirmNewPassword = !_obscureConfirmNewPassword;
              });
            },
            icon: Icon(
              _obscureConfirmNewPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurfaceVariant,
              ),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please confirm your new password';
            }
            if (value != _newPasswordController.text) {
              return 'Passwords do not match';
            }
            return null;
          },
        ),
        SizedBox(height: DesignSystem.spacingL),
        AuthButtons(
          primaryLabel: 'Change Password',
          primaryOnPressed: _changePassword,
          primaryIsLoading: _isLoading,
        ),
        SizedBox(height: DesignSystem.spacingL),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: () async {
              await _apiService.clearToken();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('is_restricted_token', false);
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: Text(
              'Back to Login',
              style: TextStyle(
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
}
