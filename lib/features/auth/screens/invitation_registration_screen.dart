import 'package:flutter/material.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/auth/widgets/legal_dialog.dart';

class InvitationRegistrationScreen extends StatefulWidget {
  final String invitationToken;

  const InvitationRegistrationScreen({
    super.key,
    required this.invitationToken,
  });

  @override
  State<InvitationRegistrationScreen> createState() =>
      _InvitationRegistrationScreenState();
}

class _InvitationRegistrationScreenState
    extends State<InvitationRegistrationScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoadingInvitation = true;
  String? _validationError;
  Map<String, dynamic>? _invitationData;

  @override
  void initState() {
    super.initState();
    _validateInvitation();
  }

  Future<void> _validateInvitation() async {
    try {
      debugPrint('[INVITATION] Validating token...');
      final response = await _apiService.validateInvitation(widget.invitationToken);

      if (!mounted) return;

      if (response['valid'] == true) {
        debugPrint('[INVITATION] Token valid');
        setState(() {
          _invitationData = response;
          _isLoadingInvitation = false;
        });
      } else {
        debugPrint('[INVITATION] Token invalid: ${response['message']}');
        setState(() {
          _validationError =
              response['message'] ?? 'Invitation not found or has expired';
          _isLoadingInvitation = false;
        });
      }
    } catch (e) {
      debugPrint('[INVITATION] Error validating token: $e');
      if (mounted) {
        setState(() {
          _validationError = 'Failed to validate invitation. Please try again.';
          _isLoadingInvitation = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInvitation) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading invitation...',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    if (_validationError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invitation Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Invitation Invalid',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  _validationError!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_invitationData == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Show invitation details with registration form
    return _InvitationRegistrationContent(
      invitationToken: widget.invitationToken,
      invitationData: _invitationData!,
    );
  }
}

class _InvitationRegistrationContent extends StatelessWidget {
  final String invitationToken;
  final Map<String, dynamic> invitationData;

  const _InvitationRegistrationContent({
    required this.invitationToken,
    required this.invitationData,
  });

  @override
  Widget build(BuildContext context) {
    final teamName = invitationData['team_name'] as String? ?? 'Team';
    final invitedEmail = invitationData['email'] as String? ?? '';
    final role = invitationData['role'] as String? ?? 'EMPLOYEE';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Team'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Invitation header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.group_add,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You\'re invited to join',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer
                              .withValues(alpha: 0.7),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    teamName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                  const SizedBox(height: 16),
                  // Invitation details
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer
                          .withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InvitationDetailRow(
                          label: 'Email',
                          value: invitedEmail,
                        ),
                        const SizedBox(height: 8),
                        _InvitationDetailRow(
                          label: 'Role',
                          value: role,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Registration form
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create Your Account',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Register using the email address this invitation was sent to',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Use existing RegisterScreen with pre-filled invitation data
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _RegisterScreenWithInvitation(
                invitationToken: invitationToken,
                invitedEmail: invitedEmail,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _InvitationDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _InvitationDetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

class _RegisterScreenWithInvitation extends StatefulWidget {
  final String invitationToken;
  final String invitedEmail;

  const _RegisterScreenWithInvitation({
    required this.invitationToken,
    required this.invitedEmail,
  });

  @override
  State<_RegisterScreenWithInvitation> createState() =>
      _RegisterScreenWithInvitationState();
}

class _RegisterScreenWithInvitationState
    extends State<_RegisterScreenWithInvitation> {
  final ApiService _apiService = ApiService();

  bool _isLoading = false;
  String? _error;

  // Form fields
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _termsAccepted = false;
  bool _dataConsent = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill email from invitation
    _emailController.text = widget.invitedEmail;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitRegistration() async {
    // Validate form
    if (_nameController.text.isEmpty) {
      setState(() => _error = 'Please enter your full name');
      return;
    }
    if (_emailController.text.isEmpty) {
      setState(() => _error = 'Email is required');
      return;
    }
    if (_emailController.text.toLowerCase() != widget.invitedEmail.toLowerCase()) {
      setState(() => _error = 'You must register with the invited email address');
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _error = 'Please enter a password');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    if (_passwordController.text.length < 12) {
      setState(() => _error = 'Password must be at least 12 characters');
      return;
    }
    if (!_termsAccepted || !_dataConsent) {
      setState(() => _error = 'Review and accept the Terms of Use and Data Privacy Notice to continue.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      debugPrint('[REGISTRATION] Registering with invitation token...');

      await _apiService.register(
        _emailController.text.toLowerCase(),
        _passwordController.text,
        _nameController.text,
        role: 'EMPLOYEE',
        accountType: 'solo',
        invitationToken: widget.invitationToken,
        termsAccepted: _termsAccepted,
        dataConsent: _dataConsent,
      );

      if (!mounted) return;

      debugPrint('[REGISTRATION] Registration successful');

      // Navigate to login screen
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully! Please log in.'),
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      debugPrint('[REGISTRATION] Registration error: $e');
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Full Name
        TextField(
          controller: _nameController,
          enabled: !_isLoading,
          decoration: InputDecoration(
            labelText: 'Full Name',
            hintText: 'Your full name',
            prefixIcon: const Icon(Icons.person),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Email (read-only, pre-filled from invitation)
        TextField(
          controller: _emailController,
          enabled: false,
          decoration: InputDecoration(
            labelText: 'Email',
            hintText: 'Your email',
            prefixIcon: const Icon(Icons.email),
            border: const OutlineInputBorder(),
            helperText: 'Must match the invitation email',
          ),
        ),
        const SizedBox(height: 16),

        // Password
        TextField(
          controller: _passwordController,
          enabled: !_isLoading,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: 'At least 6 characters',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Confirm Password
        TextField(
          controller: _confirmPasswordController,
          enabled: !_isLoading,
          obscureText: _obscureConfirmPassword,
          decoration: InputDecoration(
            labelText: 'Confirm Password',
            hintText: 'Repeat your password',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
              },
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _termsAccepted,
          onChanged: _isLoading ? null : (value) => setState(() => _termsAccepted = value ?? false),
          title: Wrap(
            children: [
              const Text('I agree to the IntelliBreak '),
              InkWell(
                onTap: () => showLegalDialog(context, LegalDoc.terms),
                child: Text('Terms of Use', style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
              ),
              const Text(' and '),
              InkWell(
                onTap: () => showLegalDialog(context, LegalDoc.privacy),
                child: Text('Data Privacy Notice', style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
              ),
              const Text('.'),
            ],
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _dataConsent,
          onChanged: _isLoading ? null : (value) => setState(() => _dataConsent = value ?? false),
          title: const Text('I consent to the collection and processing described in the Data Privacy Notice for operating IntelliBreak and evaluating this thesis system.'),
        ),
        const SizedBox(height: 16),

        // Error message
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Register button
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isLoading ? null : _submitRegistration,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create Account & Join Team'),
          ),
        ),
      ],
    );
  }
}

