import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';

import '../../../core/utils/responsive_layout.dart';
import '../../../features/auth/services/api_service.dart';
import 'package:intellibreak/features/dashboard/screens/dashboard_screen.dart';

class TotpChallengeScreen extends StatefulWidget {
  final String challengeToken;

  const TotpChallengeScreen({Key? key, required this.challengeToken})
    : super(key: key);

  @override
  State<TotpChallengeScreen> createState() => _TotpChallengeScreenState();
}

class _TotpChallengeScreenState extends State<TotpChallengeScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _totpController = TextEditingController();
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  void _verifyTotp() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final loginData = await _apiService.verifyLogin2fa(
          widget.challengeToken,
          _totpController.text.trim(),
        );

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
          );
        }
      } on Exception catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
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
  void dispose() {
    _totpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ResponsiveLayout(
        desktop: _buildDesktopTotpChallenge(isDark),
        tablet: _buildTabletTotpChallenge(isDark),
        mobile: _buildMobileTotpChallenge(isDark),
      ),
    );
  }

  Widget _buildMobileTotpChallenge(bool isDark) =>
      _buildFullPageTotpChallenge(isDark);

  Widget _buildTabletTotpChallenge(bool isDark) =>
      _buildFullPageTotpChallenge(isDark);

  Widget _buildDesktopTotpChallenge(bool isDark) =>
      _buildFullPageTotpChallenge(isDark);

  Widget _buildFullPageTotpChallenge(bool isDark) {
    return Stack(
      children: [
        // Theme toggle (top-right)
        Positioned(
          top: 24,
          right: 24,
          child: Builder(
            builder: (context) => IconButton(
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
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _buildTotpChallengeCard(isDark),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTotpChallengeCard(bool isDark) {
    final Color cardBgColor = isDark ? Color(0xFF222532) : Color(0xFFECEFF3);
    final Color cardBorderColor = isDark
        ? Color(0xFF303442)
        : Color(0xFFD3D9E1);
    final Color logoBgColor = Color(0xFF0F766E);
    final Color logoIconColor = Colors.white;
    final Color titleTextColor = isDark ? Colors.white : Color(0xFF111827);
    final Color subtitleTextColor = isDark
        ? Color(0xFF9CA3AF)
        : Color(0xFF5B6472);
    final Color labelTextColor = isDark ? Colors.white : Color(0xFF111827);
    final Color textFieldTextColor = isDark ? Colors.white : Color(0xFF111827);
    final Color verifyButtonBgColor = Color(0xFF0F766E);
    final Color verifyButtonFgColor = Colors.white;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorderColor),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: logoBgColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.bolt_rounded, color: logoIconColor, size: 36),
              ),
            ),
            const SizedBox(height: 24),
            // Title
            Center(
              child: Text(
                'Two-Factor Authentication',
                style: TextStyle(
                  color: titleTextColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Enter the 6-digit code from your authenticator app',
                textAlign: TextAlign.center,
                style: TextStyle(color: subtitleTextColor, fontSize: 14),
              ),
            ),
            const SizedBox(height: 32),
            // TOTP Code
            Text(
              'Authentication Code',
              style: TextStyle(
                color: labelTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _totpController,
              keyboardType: TextInputType.number,
              obscureText: false,
              style: TextStyle(color: textFieldTextColor),
              decoration: _inputDecoration(
                hintText: 'Enter 6-digit code',
                icon: Icons.lock_outlined,
                isDark: isDark,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter the authentication code';
                }
                if (value.trim().length != 6) {
                  return 'Please enter a valid 6-digit code';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            // Verify button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyTotp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: verifyButtonBgColor,
                  foregroundColor: verifyButtonFgColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Verify',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
    required bool isDark,
  }) {
    final Color hintTextColor = isDark ? Color(0xFF5B6472) : Color(0xFF5B6472);
    final Color prefixIconColor = isDark
        ? Color(0xFF9CA3AF)
        : Color(0xFF5B6472);
    final Color fillColor = isDark ? Color(0xFF111827) : Colors.white;
    final Color borderColor = isDark ? Color(0xFF303442) : Color(0xFFD3D9E1);
    final Color focusedBorderColor = Color(0xFF0F766E);

    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: hintTextColor, fontSize: 14),
      prefixIcon: Icon(icon, color: prefixIconColor, size: 20),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: focusedBorderColor, width: 1.5),
      ),
    );
  }
}
