import 'package:flutter/material.dart';
import 'package:intellibreak/features/team/team_service.dart';
import 'package:intellibreak/providers/team_provider.dart';

class InviteEmployeePickerDialog extends StatefulWidget {
  final String teamId;
  final String token;
  final TeamProvider teamProvider;
  final VoidCallback onInvitationSent;

  const InviteEmployeePickerDialog({
    super.key,
    required this.teamId,
    required this.token,
    required this.teamProvider,
    required this.onInvitationSent,
  });

  @override
  State<InviteEmployeePickerDialog> createState() => _InviteEmployeePickerDialogState();
}

class _InviteEmployeePickerDialogState extends State<InviteEmployeePickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TeamService _teamService = TeamService();

  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedUser;
  bool _isSearching = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final results = await _teamService.searchUsersForInvitation(
        widget.teamId,
        query,
        widget.token,
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Search failed: $e';
          _searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    // Debounce search
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_searchController.text.trim() == query) {
        _performSearch(query);
      }
    });
  }

  void _selectUser(Map<String, dynamic> user) {
    setState(() {
      _selectedUser = user;
      _searchResults = [];
      _searchController.clear();
    });
  }

  void _removeSelected() {
    setState(() {
      _selectedUser = null;
    });
  }

  Future<void> _sendInvitation() async {
    if (_selectedUser == null) return;

    setState(() => _isLoading = true);

    try {
      await widget.teamProvider.sendInvitation(
        widget.token,
        widget.teamId,
        _selectedUser!['email'] as String,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invitation sent to ${_selectedUser!['full_name']}'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onInvitationSent();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to send invitation: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: const Text('Invite Employee'),
      titlePadding: const EdgeInsets.all(16),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search field
              Text(
                'Search for a person',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by name or email...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              // Error message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),

              // Search results
              if (_searchController.text.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search results',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isSearching)
                      const SizedBox(
                        height: 60,
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else if (_searchResults.isEmpty)
                      SizedBox(
                        height: 60,
                        child: Center(
                          child: Text(
                            'No matching employees found',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, index) => Divider(
                            height: 1,
                            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                          ),
                          itemBuilder: (context, index) {
                            final user = _searchResults[index];
                            final status = user['status'] as String?;
                            final canSelect = status == 'available';

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: canSelect ? () => _selectUser(user) : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                                child: Text(
                                                  (() {
                                                    final name = user['full_name'].toString();
                                                    final initials = name
                                                        .split(' ')
                                                        .where((s) => s.isNotEmpty)
                                                        .map((e) => e[0])
                                                        .join()
                                                        .toUpperCase();
                                                    return initials.substring(0,
                                                        initials.length > 2 ? 2 : initials.length);
                                                  })(),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: isDark ? Colors.white : Colors.black,
                                                  ),
                                                ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  user['full_name'] as String,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                    color: isDark ? Colors.white : Colors.black,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  user['email'] as String,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (status != 'available')
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                status == 'already_member'
                                                    ? 'Member'
                                                    : status == 'pending_invitation'
                                                        ? 'Pending'
                                                        : 'N/A',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.orange,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),

              // Selected user
              if (_selectedUser != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.blue.withValues(alpha: 0.05),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                (() {
                                  final name = _selectedUser!['full_name'].toString();
                                  final initials = name
                                      .split(' ')
                                      .where((s) => s.isNotEmpty)
                                      .map((e) => e[0])
                                      .join()
                                      .toUpperCase();
                                  return initials.substring(0,
                                      initials.length > 2 ? 2 : initials.length);
                                })(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedUser!['full_name'] as String,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _selectedUser!['email'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _removeSelected,
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Remove'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedUser == null || _isLoading ? null : _sendInvitation,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send Invitation'),
        ),
      ],
    );
  }
}
