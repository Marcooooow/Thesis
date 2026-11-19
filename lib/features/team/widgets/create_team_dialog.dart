import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/providers/team_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dialog for creating a new team.
class CreateTeamDialog extends StatefulWidget {
  final VoidCallback? onTeamCreated;

  const CreateTeamDialog({
    super.key,
    this.onTeamCreated,
  });

  @override
  State<CreateTeamDialog> createState() => _CreateTeamDialogState();
}

class _CreateTeamDialogState extends State<CreateTeamDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Validate inputs and create the team.
  Future<void> _submitForm() async {
    final name = _nameController.text.trim();

    // Validation
    if (name.isEmpty) {
      setState(() {
        _error = 'Team name is required';
      });
      return;
    }

    if (name.length < 2) {
      setState(() {
        _error = 'Team name must be at least 2 characters';
      });
      return;
    }

    if (name.length > 100) {
      setState(() {
        _error = 'Team name must be 100 characters or less';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Get provider and description BEFORE async operations
    final teamProvider = context.read<TeamProvider>();
    final description = _descriptionController.text.trim();

    try {
      // Get the authentication token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'Authentication token not found';
        });
        return;
      }

      // Create the team
      final team = await teamProvider.createTeam(
        token,
        name,
        description: description.isNotEmpty ? description : null,
      );

      if (!mounted) return;

      if (team != null) {
        // Success: close dialog and notify
        Navigator.of(context).pop(true);
        widget.onTeamCreated?.call();

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Team "${team.name}" created successfully'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Error from provider
        setState(() {
          _isLoading = false;
          _error = teamProvider.error ?? 'Failed to create team';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'An error occurred: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Team'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Error message display
            if (_error != null)
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 14,
                  ),
                  maxLines: null,
                  overflow: TextOverflow.visible,
                ),
              ),

            // Team Name Field
            TextField(
              controller: _nameController,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: 'Team Name *',
                hintText: 'e.g., Engineering Team',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              maxLength: 100,
            ),
            const SizedBox(height: 16),

            // Team Description Field
            TextField(
              controller: _descriptionController,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Team description...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 16),

          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitForm,
          child: _isLoading
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                )
              : const Text('Create Team'),
        ),
      ],
    );
  }
}
