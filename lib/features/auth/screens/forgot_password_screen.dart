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

import 'reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  @override
  void dispose() {
    _emailController.dispose();
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
        final response = await _apiService.forgotPassword(
          _emailController.text.trim(),
        );
        String message = 'Check your email for the reset token.';
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
          // Navigate to reset password screen after a short delay to allow snackbar to appear
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              navigator.push(
                MaterialPageRoute(
                  builder: (_) => ResetPasswordScreen(
                    token: response.containsKey('reset_token')
                        ? response['reset_token'] as String
                        : null,
                  ),
                ),
              );
            }
          });
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Failed to send reset email: $e'),
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
        desktop: _buildDesktopForgotPassword(context),
        tablet: _buildTabletForgotPassword(context),
        mobile: _buildMobileForgotPassword(context),
      ),
    );
  }

  Widget _buildMobileForgotPassword(BuildContext context) =>
      _buildFullPageForgotPassword(context, maxWidth: 400);

  Widget _buildTabletForgotPassword(BuildContext context) =>
      _buildFullPageForgotPassword(context, maxWidth: 400);

  Widget _buildDesktopForgotPassword(BuildContext context) =>
      _buildFullPageForgotPassword(context, maxWidth: 400);

  Widget _buildFullPageForgotPassword(BuildContext context, {double maxWidth = 400}) {
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
                child: AuthCard(child: _buildForgotPasswordForm(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForgotPasswordForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthLogo(),
          SizedBox(height: DesignSystem.spacingL),
          const AuthHeader(
            title: 'Forgot Password',
            subtitle: 'Enter your email to receive password reset instructions',
          ),
          SizedBox(height: DesignSystem.spacingXL),
          AuthFormField(
            label: 'Email',
            hintText: 'Enter your email',
            controller: _emailController,
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email';
              }
              if (!value.contains('@')) {
                return 'Please enter a valid email';
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
                'Sign In',
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
