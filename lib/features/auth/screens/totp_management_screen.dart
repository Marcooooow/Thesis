import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';

import '../../../core/utils/responsive_layout.dart';
import '../../../features/auth/services/api_service.dart';

class TotpManagementScreen extends StatefulWidget {
  const TotpManagementScreen({Key? key}) : super(key: key);

  @override
  State<TotpManagementScreen> createState() => _TotpManagementScreenState();
}

class _TotpManagementScreenState extends State<TotpManagementScreen> {
  bool _isLoading = false;
  bool _is2faEnabled = false;
  String? _secret;
  String? _provisioningUri;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _load2faStatus();
  }

  Future<void> _load2faStatus() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final token = await _apiService.getToken();
      if (token == null) {
        if (mounted) {
          // Navigate to login if no token
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login', (Route<dynamic> route) => false);
        }
        return;
      }

      final userInfo = await _apiService.getMe(token);
      setState(() {
        _is2faEnabled = userInfo['is_2fa_enabled'] ?? false;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // Handle error appropriately
      }
    }
  }

  Future<void> _setupTotp() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final token = await _apiService.getToken();
      if (token == null) throw Exception('No authentication token');

      final response = await _apiService.setupTotp(token);
      setState(() {
        _secret = response['secret'];
        _provisioningUri = response['provisioning_uri'];
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // Show error message
      }
    }
  }

  Future<void> _verifyAndEnableTotp(String totpToken) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final token = await _apiService.getToken();
      if (token == null) throw Exception('No authentication token');

      await _apiService.verifyTotpSetup(token, totpToken);
      setState(() {
        _is2faEnabled = true;
        _isLoading = false;
      });
      // Clear temporary data
      setState(() {
        _secret = null;
        _provisioningUri = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // Show error message
      }
    }
  }

  Future<void> _disableTotp(String password, String totpToken) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final token = await _apiService.getToken();
      if (token == null) throw Exception('No authentication token');

      await _apiService.disableTotp(token, password, totpToken);
      setState(() {
        _is2faEnabled = false;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // Show error message
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ResponsiveLayout(
        desktop: _buildDesktopTotpManagement(isDark),
        tablet: _buildTabletTotpManagement(isDark),
        mobile: _buildMobileTotpManagement(isDark),
      ),
    );
  }

  Widget _buildMobileTotpManagement(bool isDark) =>
      _buildFullPageTotpManagement(isDark);

  Widget _buildTabletTotpManagement(bool isDark) =>
      _buildFullPageTotpManagement(isDark);

  Widget _buildDesktopTotpManagement(bool isDark) =>
      _buildFullPageTotpManagement(isDark);

  Widget _buildFullPageTotpManagement(bool isDark) {
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
              child: _buildTotpManagementCard(isDark),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTotpManagementCard(bool isDark) {
    final Color cardBgColor = isDark ? Color(0xFF222532) : Color(0xFFF8F9FA);
    final Color cardBorderColor = isDark
        ? Color(0xFF303442)
        : Color(0xFFE0E0E0);

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorderColor),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_is2faEnabled && _secret == null && _provisioningUri == null
          ? _buildSetupSection(isDark)
          : _is2faEnabled
          ? _buildEnabledSection(isDark)
          : _buildVerificationSection(isDark),
    );
  }

  Widget _buildSetupSection(bool isDark) {
    final Color logoBgColor = Color(0xFF6C63FF);
    final Color logoIconColor = Colors.white;
    final Color titleTextColor = isDark ? Colors.white : Color(0xFF171923);
    final Color subtitleTextColor = isDark
        ? Color(0xFF9CA3AF)
        : Color(0xFF6B7280);
    final Color buttonBgColor = Color(0xFF6C63FF);
    final Color buttonFgColor = Colors.white;

    return Column(
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
            'Set up Two-Factor Authentication',
            style: TextStyle(
              color: titleTextColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Scan the QR code with your authenticator app (Google Authenticator, Authy, etc.)',
            textAlign: TextAlign.center,
            style: TextStyle(color: subtitleTextColor, fontSize: 14),
          ),
        ),
        const SizedBox(height: 32),
        // Setup button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _setupTotp,
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonBgColor,
              foregroundColor: buttonFgColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Set up 2FA',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationSection(bool isDark) {
    final totpController = TextEditingController();
    final Color logoBgColor = Color(0xFF6C63FF);
    final Color logoIconColor = Colors.white;
    final Color titleTextColor = isDark ? Colors.white : Color(0xFF171923);
    final Color labelTextColor = isDark ? Colors.white : Color(0xFF171923);
    final Color textFieldTextColor = isDark ? Colors.white : Color(0xFF171923);
    final Color buttonBgColor = Color(0xFF6C63FF);
    final Color buttonFgColor = Colors.white;

    return Column(
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
            'Verify and Enable Two-Factor Authentication',
            style: TextStyle(
              color: titleTextColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // QR Code placeholder (in a real app, you'd display an actual QR code image)
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: isDark ? Color(0xFF303442) : Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              'QR Code\nScan with\nAuthenticator App',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Or enter the secret key manually:',
          style: TextStyle(
            color: labelTextColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _secret ?? '',
          style: TextStyle(
            color: textFieldTextColor,
            fontSize: 16,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Enter the 6-digit code from your authenticator app:',
          style: TextStyle(
            color: labelTextColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: totpController,
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
            onPressed: () {
              final token = totpController.text.trim();
              if (token.isNotEmpty) {
                _verifyAndEnableTotp(token);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonBgColor,
              foregroundColor: buttonFgColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Verify and Enable',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnabledSection(bool isDark) {
    final Color logoBgColor = Color(0xFF6C63FF);
    final Color logoIconColor = Colors.white;
    final Color titleTextColor = isDark ? Colors.white : Color(0xFF171923);
    final Color subtitleTextColor = isDark
        ? Color(0xFF9CA3AF)
        : Color(0xFF6B7280);

    return Column(
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
            'Two-Factor Authentication Enabled',
            style: TextStyle(
              color: titleTextColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Your account is protected with two-factor authentication.',
            textAlign: TextAlign.center,
            style: TextStyle(color: subtitleTextColor, fontSize: 14),
          ),
        ),
        const SizedBox(height: 32),
        // Disable button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () {
              // Show dialog to enter password and TOTP code
              final passwordController = TextEditingController();
              final totpController = TextEditingController();
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Disable Two-Factor Authentication'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Please enter your password and the 6-digit code from your authenticator app:',
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: passwordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: totpController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'TOTP Code',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          final password = passwordController.text;
                          final totpToken = totpController.text;
                          Navigator.of(context).pop();
                          _disableTotp(password, totpToken);
                        },
                        child: const Text('Disable'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Disable 2FA',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
    required bool isDark,
  }) {
    final Color hintTextColor = isDark ? Color(0xFF6B7280) : Color(0xFF6B7280);
    final Color prefixIconColor = isDark
        ? Color(0xFF9CA3AF)
        : Color(0xFF6B7280);
    final Color fillColor = isDark ? Color(0xFF171923) : Colors.white;
    final Color borderColor = isDark ? Color(0xFF303442) : Color(0xFFE0E0E0);
    final Color focusedBorderColor = Color(0xFF6C63FF);

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
