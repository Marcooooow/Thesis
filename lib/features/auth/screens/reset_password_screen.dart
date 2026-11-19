import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/auth/widgets/auth_buttons.dart';
import 'package:intellibreak/features/auth/widgets/auth_card.dart';
import 'package:intellibreak/features/auth/widgets/auth_layout.dart';
import 'package:intellibreak/features/auth/widgets/auth_logo.dart';
import 'package:intellibreak/features/auth/widgets/auth_form_field.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/auth/widgets/auth_header.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? token; // Token can be passed as a route argument

  const ResetPasswordScreen({Key? key, this.token}) : super(key: key);

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    // If token is provided via route argument, populate the token field
    if (widget.token != null) {
      _tokenController.text = widget.token!;
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      try {
        final response = await _apiService.resetPassword(
          _tokenController.text.trim(),
          _passwordController.text.trim(),
        );
        // Assuming the backend returns a success message
        String message = 'Password has been reset successfully.';
        if (response.containsKey('message')) {
          message = response['message'];
        }
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: DesignSystem.getSemanticColor(
                context,
                SemanticColor.success,
              ),
            ),
          );
          // Navigate to login screen after successful reset
          // Optionally, wait a bit before navigating
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              navigator.pushNamedAndRemoveUntil(
                '/login',
                (Route<dynamic> route) => false,
              );
            }
          });
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Failed to reset password: $e'),
              backgroundColor: DesignSystem.getSemanticColor(
                context,
                SemanticColor.error,
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: AuthLayout(
        desktop: _buildDesktopResetPassword(context),
        tablet: _buildTabletResetPassword(context),
        mobile: _buildMobileResetPassword(context),
      ),
    );
  }

  Widget _buildMobileResetPassword(BuildContext context) =>
      _buildFullPageResetPassword(context, maxWidth: 400);

  Widget _buildTabletResetPassword(BuildContext context) =>
      _buildFullPageResetPassword(context, maxWidth: 400);

  Widget _buildDesktopResetPassword(BuildContext context) =>
      _buildFullPageResetPassword(context, maxWidth: 400);

  Widget _buildFullPageResetPassword(BuildContext context, {double maxWidth = 400}) {
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
                child: AuthCard(child: _buildResetPasswordForm(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetPasswordForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthLogo(),
        SizedBox(height: DesignSystem.spacingL),
        const AuthHeader(
          title: 'Reset Password',
          subtitle: 'Enter the reset token and your new password',
        ),
        SizedBox(height: DesignSystem.spacingXL),
        AuthFormField(
          label: 'Reset Token',
          hintText: 'Enter the reset token from your email',
          controller: _tokenController,
          prefixIcon: Icons.vpn_key_outlined,
          obscureText: false,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter the reset token';
            }
            return null;
          },
        ),
        SizedBox(height: DesignSystem.spacingL),
        AuthFormField(
          label: 'New Password',
          hintText: 'Enter new password',
          controller: _passwordController,
          prefixIcon: Icons.lock_outlined,
          obscureText: true,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter a password';
            }
            if (value.trim().length < 6) {
              return 'Password must be at least 6 characters long';
            }
            return null;
          },
        ),
        SizedBox(height: DesignSystem.spacingL),
        AuthFormField(
          label: 'Confirm New Password',
          hintText: 'Confirm new password',
          controller: _confirmPasswordController,
          prefixIcon: Icons.lock_outlined,
          obscureText: true,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please confirm your password';
            }
            if (value.trim() != _passwordController.text.trim()) {
              return 'Passwords do not match';
            }
            return null;
          },
        ),
        SizedBox(height: DesignSystem.spacingL),
        AuthButtons(
          primaryLabel: 'Reset Password',
          primaryOnPressed: _resetPassword,
          primaryIsLoading: _isLoading,
        ),
        SizedBox(height: DesignSystem.spacingL),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
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
    );
  }
}
