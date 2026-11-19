import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/providers/team_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dialog for inviting an employee to the team.
class InviteEmployeeDialog extends StatefulWidget {
  final String teamId;
  final VoidCallback? onInvitationSent;

  const InviteEmployeeDialog({
    super.key,
    required this.teamId,
    this.onInvitationSent,
  });

  @override
  State<InviteEmployeeDialog> createState() => _InviteEmployeeDialogState();
}

class _InviteEmployeeDialogState extends State<InviteEmployeeDialog> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Validate email format.
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  /// Submit the invitation.
  Future<void> _submitForm() async {
    final email = _emailController.text.trim();

    // Validation
    if (email.isEmpty) {
      setState(() {
        _error = 'Email is required';
      });
      return;
    }

    if (!_isValidEmail(email)) {
      setState(() {
        _error = 'Please enter a valid email address';
      });
      return;
    }

    if (email.length > 255) {
      setState(() {
        _error = 'Email is too long';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (!mounted) return;

      if (token == null) {
        setState(() {
          _error = 'Authentication token not found';
          _isLoading = false;
        });
        return;
      }

      final teamProvider = context.read<TeamProvider>();
      final success = await teamProvider.sendInvitation(
        token,
        widget.teamId,
        email,
      );

      if (!mounted) return;

      if (success) {
        widget.onInvitationSent?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invitation sent to $email'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _error = teamProvider.error ?? 'Failed to send invitation';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite Employee'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _emailController,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: 'Employee Email',
                hintText: 'employee@example.com',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitForm,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send Invitation'),
        ),
      ],
    );
  }
}
