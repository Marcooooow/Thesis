import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/auth/widgets/auth_card.dart';
import 'package:intellibreak/features/auth/widgets/auth_layout.dart';
import 'package:intellibreak/features/auth/widgets/auth_logo.dart';
import 'package:intellibreak/features/auth/widgets/auth_form_field.dart';
import 'package:intellibreak/features/auth/widgets/auth_header.dart';

import '../services/api_service.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'change_password_screen.dart';
import '../../../routes/auth_gate.dart';
import 'totp_challenge_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isLoading = false;
  String? _statusMessage;

  void _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final apiService = ApiService();

      try {
        setState(() => _statusMessage = 'Connecting to IntelliBreak server...');
        final loginData = await apiService.login(
          _emailController.text.trim(),
          _passwordController.text,
        );

        if (loginData['requires_2fa'] && mounted) {
          // Save the challenge token temporarily for 2FA verification
          final String challengeToken = loginData['access_token'];
          if (!mounted) return;

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  TotpChallengeScreen(challengeToken: challengeToken),
            ),
          );
        } else if (loginData.containsKey('message') &&
                   loginData['message'] == 'Password change required' && mounted) {
          // Handle restricted first-login token - navigate to change password screen
          // Token is already saved by apiService.login()
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            (route) => false,
          );
        } else {
          if (mounted) {
            setState(() => _statusMessage = null);
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthGate()),
              (route) => false,
            );
          }
        }
      } on Exception catch (e) {
        final msg = e.toString();
        if (msg.contains('after 5 attempts') || msg.contains('connection timed out') ||
            msg.contains('Backend unavailable')) {
          if (mounted) setState(() => _statusMessage = 'Server is waking up. Please wait...');
        } else {
          if (mounted) setState(() => _statusMessage = null);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusMessage = null;
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
        desktop: _buildDesktopLogin(context),
        tablet: _buildTabletLogin(context),
        mobile: _buildMobileLogin(context),
      ),
    );
  }

  Widget _buildMobileLogin(BuildContext context) => _buildFullPageLogin(context);

  Widget _buildTabletLogin(BuildContext context) => _buildFullPageLogin(context);

  Widget _buildDesktopLogin(BuildContext context) => _buildFullPageLogin(context);

  Widget _buildFullPageLogin(BuildContext context) {
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
                constraints: const BoxConstraints(maxWidth: 400),
                child: AuthCard(child: _buildLoginForm(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthLogo(),
          SizedBox(height: DesignSystem.spacingL),
          const AuthHeader(
            title: 'Welcome back',
            subtitle: 'Sign in to continue to IntelliBreak',
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
          AuthFormField(
            label: 'Password',
            hintText: 'Enter your password',
            controller: _passwordController,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
              icon: Icon(
                _obscurePassword
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
                return 'Please enter your password';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
            onSubmitted: (_) => _login(),
          ),
          SizedBox(height: DesignSystem.spacingS),
          // Remember me + Forgot password
          Row(
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (value) {
                  setState(() {
                    _rememberMe = value ?? false;
                  });
                },
                activeColor: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.primary,
                ),
                checkColor: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurface,
                ),
                side: BorderSide(
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.onSurfaceVariant,
                  ).withValues(alpha: 0.5),
                ),
              ),
              Text(
                'Remember me',
                style: TextStyle(
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.onSurfaceVariant,
                  ),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          ForgotPasswordScreen(),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                    ),
                  );
                },
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.primary,
                    ),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  fontSize: 13,
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.primary,
                  ),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          // Login button
          SizedBox(
            width: double.infinity,
            child: DesignSystem.primaryButton(
              context: context,
              label: 'Sign In',
              onPressed: _login,
              isLoading: _isLoading,
            ),
          ),
          const SizedBox(height: 16),
          // Register
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        RegisterScreen(),
                    transitionsBuilder: (
                      context,
                      animation,
                      secondaryAnimation,
                      child,
                    ) => FadeTransition(opacity: animation, child: child),
                  ),
                );
              },
              child: Text(
                'Create account',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
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
