import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/admin/services/admin_service.dart';
import 'package:intellibreak/features/admin/screens/employee_details_screen.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final AdminService _adminService = AdminService();
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String? _token;
  List<dynamic> _users = [];
  List<dynamic> _filteredUsers = [];
  String _userRole = 'UNKNOWN';

  // Pagination variables
  int _currentPage = 1;
  int _limit = 25;
  int _totalUsers = 0;
  int _totalPages = 1;

  // Filter controllers and variables
  final TextEditingController _searchController = TextEditingController();
  String _selectedRoleFilter = 'All Roles';
  String _selectedStatusFilter = 'All Status';
  String? _selectedEmployeeId;

  // Available filter options
  List<String> _roleFilters = ['All Roles'];
  final List<String> _statusFilters = [
    'All Status',
    'PENDING',
    'APPROVED',
    'REJECTED',
  ];

  // Debouncer & request sequencing
  Timer? _searchTimer;
  int _latestRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _token = token;
      _isLoading = true;
    });

    if (token != null) {
      try {
        final userData = await _apiService.getMe(token);
        final role = userData['role'];
        if (!mounted) return;
        setState(() {
          _userRole = role;
        });

        // Load users data
        await _loadUsers(token);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'Failed to load user information';
        });
      }
    } else {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'No authentication token found';
      });
    }
  }

  final ApiService _apiService = ApiService();

  Future<void> _loadUsers(String token) async {
    final int requestId = ++_latestRequestId;
    try {
      final response = await _adminService.getAllUsers(
        token,
        page: _currentPage,
        limit: _limit,
        search: _searchController.text.isNotEmpty
            ? _searchController.text
            : null,
        role: _selectedRoleFilter != 'All Roles' ? _selectedRoleFilter : null,
        status: _selectedStatusFilter != 'All Status'
            ? _selectedStatusFilter
            : null,
      );
      if (!mounted || requestId != _latestRequestId) return;
      setState(() {
        final List<dynamic> usersList = response['users'] ?? [];
        _users = usersList;
        _filteredUsers = usersList;
        _totalUsers = response['total'] ?? 0;
        _totalPages = response['total_pages'] ?? 1;
        _currentPage = response['page'] ?? 1;
        _updateFilterOptions();
        _isLoading = false;
        _hasError = false;
      });
    } catch (e) {
      if (!mounted || requestId != _latestRequestId) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Failed to load users: $e';
      });
    }
  }

  // Sort by created desc (newest first) then older
  void _applyFilters() {
    _searchTimer?.cancel();
    setState(() {
      _currentPage = 1;
    });
    if (_token != null) {
      _loadUsers(_token!);
    }
  }

  void _updateFilterOptions() {
    // Update role filters based on users
    final Set<String> roles = {'All Roles'};
    for (final user in _users) {
      final String role = user['role'] ?? 'UNKNOWN';
      roles.add(role);
    }
    _roleFilters = roles.toList();

    // Status filters are predefined
  }

  Future<void> _refreshUsers() async {
    await _loadUsers(_token!);
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;

    if (_selectedEmployeeId != null) {
      return EmployeeDetailsScreen(
        employeeId: _selectedEmployeeId!,
        onBack: () => setState(() => _selectedEmployeeId = null),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshUsers,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
          ? _buildErrorView(isDark, isHighContrast)
          : _buildAccountsView(context, isDark, isHighContrast, isDesktop),
    );
  }

  Widget _buildErrorView(bool isDark, bool isHighContrast) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: isDark
                  ? (isHighContrast ? Colors.white : Colors.redAccent)
                  : Colors.red,
              size: 48,
            ),
            const SizedBox(height: 24),
            Text(
              'Error Loading Accounts',
              style: TextStyle(
                color: isDark
                    ? (isHighContrast ? Colors.white : Colors.white)
                    : Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'An unknown error occurred',
              style: TextStyle(
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : Color(0xFFA5A7AE))
                    : Colors.grey.shade600,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _refreshUsers,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark
                    ? (isHighContrast ? Colors.white : Color(0xFF2A2D3A))
                    : Colors.blue,
                foregroundColor: isDark
                    ? (isHighContrast ? Colors.black : Colors.white)
                    : Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountsView(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    bool isDesktop,
  ) {
    // Initialize filter controllers if not already done
    if (_searchController.text.isEmpty) {
      _searchController.text = '';
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 24 : 16,
              isDesktop ? 24 : 16,
              isDesktop ? 24 : 16,
              isDesktop ? 24 : 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.people, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Accounts Management',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? (isHighContrast ? Colors.white : Colors.white)
                            : Colors.black,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Add User Button
                if (_userRole == 'ADMIN')
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _showAddUserDialog,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add New User'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DesignSystem.getSemanticColor(
                          context,
                          SemanticColor.success,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // Filter bar
                _buildFilterBar(context, isDark, isHighContrast, isDesktop),
                const SizedBox(height: 16),
                // Users list
                if (_filteredUsers.isEmpty)
                  _buildEmptyState(isDark, isHighContrast),
              ],
            ),
          ),
        ),
        if (_filteredUsers.isNotEmpty) ...[
          SliverPadding(
            padding: EdgeInsets.zero,
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final user = _filteredUsers[index];
                  return _buildUserCard(user, isDark, isHighContrast);
                },
                childCount: _filteredUsers.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildPaginationBar(isDark, isHighContrast, isDesktop),
          ),
        ],
      ],
    );
  }

  Widget _buildPaginationBar(bool isDark, bool isHighContrast, bool isDesktop) {
    if (_totalPages <= 1 && _totalUsers <= _limit) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 24 : 16,
        16,
        isDesktop ? 24 : 16,
        24,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Page $_currentPage of $_totalPages (Total: $_totalUsers accounts)',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? (isHighContrast ? Colors.white70 : const Color(0xFFA5A7AE))
                  : Colors.grey.shade600,
            ),
          ),
          Row(
            children: [
              ElevatedButton(
                onPressed: _currentPage > 1
                    ? () {
                        setState(() {
                          _currentPage--;
                        });
                        _loadUsers(_token!);
                      }
                    : null,
                child: const Text('Previous'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _currentPage < _totalPages
                    ? () {
                        setState(() {
                          _currentPage++;
                        });
                        _loadUsers(_token!);
                      }
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, bool isHighContrast) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(48),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.5)
                        : Color(0xFFA5A7AE))
                  : Colors.grey.shade400,
            ),
            const SizedBox(height: 24),
            Text(
              'No Accounts Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? (isHighContrast ? Colors.white : Colors.white)
                    : Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'No accounts match the current filters.',
              style: TextStyle(
                fontSize: 16,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : Color(0xFFA5A7AE))
                    : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(dynamic user, bool isDark, bool isHighContrast) {
    final String name = user['full_name'] ?? 'Unknown User';
    final String email = user['email'] ?? '';
    final String role = user['role'] ?? 'UNKNOWN';
    final String approvalStatus = user['approval_status'] ?? 'UNKNOWN';
    final bool isActive = user['is_active'] ?? false;
    final String organizationName = user['organization_name'] ?? '';

    // Status indicator — account status (separate from online presence)
    String statusText = 'Offline';
    Color statusColor = Colors.grey;

    if (!isActive) {
      statusText = 'Inactive';
      statusColor = Colors.red;
    } else if (approvalStatus == 'PENDING') {
      statusText = 'Pending Approval';
      statusColor = Colors.orange;
    } else if (approvalStatus == 'APPROVED') {
      statusText = 'Active';
      statusColor = Colors.green;
    } else if (approvalStatus == 'REJECTED') {
      statusText = 'Rejected';
      statusColor = Colors.red;
    }

    return DesignSystem.premiumCard(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDark
                        ? (isHighContrast ? Colors.white : Colors.grey.shade700)
                        : Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    color: isDark
                        ? (isHighContrast ? Colors.black : Colors.white)
                        : Colors.grey.shade800,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? (isHighContrast ? Colors.white : Colors.white)
                              : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? (isHighContrast
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : Color(0xFFA5A7AE))
                              : Colors.grey.shade600,
                        ),
                      ),
                      if (organizationName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Organization: $organizationName',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? (isHighContrast
                                      ? Colors.white.withValues(alpha: 0.6)
                                      : Color(0xFFA5A7AE))
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'Role: $role',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? (isHighContrast
                                        ? Colors.white.withValues(alpha: 0.6)
                                        : Color(0xFFA5A7AE))
                                  : Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Status: $approvalStatus',
                            style: TextStyle(
                              fontSize: 12,
                              color: approvalStatus == 'APPROVED'
                                  ? Colors.green
                                  : approvalStatus == 'PENDING'
                                  ? Colors.orange
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    if (_userRole == 'ADMIN') ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 80,
                        child: ElevatedButton(
                          onPressed: () => _showUserActionsDialog(user),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DesignSystem.getSemanticColor(
                              context,
                              SemanticColor.primary,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text(
                            'Actions',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(
              height: 1,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.1)
                        : Color(0xFF30323A))
                  : Colors.grey.withValues(alpha: 0.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    bool isDesktop,
  ) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 24 : 16,
          vertical: isDesktop ? 16 : 12,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? (isHighContrast
                    ? const Color(0xFF0D0D0D)
                    : const Color(0xFF1B1D24))
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: isDark
                ? (isHighContrast
                      ? Colors.white.withValues(alpha: 0.1)
                      : const Color(0xFF30323A))
                : const Color(0xFFE0E0E0),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or email...',
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark
                      ? (isHighContrast
                            ? Colors.white.withValues(alpha: 0.7)
                            : Color(0xFFA5A7AE))
                      : Colors.grey.shade600,
                ),
                filled: true,
                fillColor: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.05)
                          : Color(0xFF2A2D3A))
                    : Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: TextStyle(
                color: isDark
                    ? (isHighContrast ? Colors.white : Colors.white)
                    : Colors.black,
              ),
              onChanged: (value) {
                _searchTimer?.cancel();
                _searchTimer = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    _applyFilters();
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            // Filter chips row
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Role filter
                FilterChip(
                  label: Text(
                    _selectedRoleFilter,
                    style: TextStyle(
                      color: isDark
                          ? (isHighContrast ? Colors.white : Colors.white)
                          : Colors.black,
                    ),
                  ),
                  selected: _selectedRoleFilter != 'All Roles',
                  onSelected: (selected) {
                    if (selected) {
                      // Show role filter dropdown
                      _showFilterDialog(
                        context,
                        'Filter by Role',
                        _roleFilters,
                        _selectedRoleFilter,
                        (value) {
                          setState(() {
                            _selectedRoleFilter = value;
                            _applyFilters();
                          });
                        },
                      );
                    } else {
                      setState(() {
                        _selectedRoleFilter = 'All Roles';
                        _applyFilters();
                      });
                    }
                  },
                  backgroundColor: isDark
                      ? (isHighContrast
                            ? Colors.white.withValues(alpha: 0.05)
                            : Color(0xFF2A2D3A))
                      : Colors.grey.shade100,
                  selectedColor: isDark
                      ? (isHighContrast
                            ? Colors.blue.withValues(alpha: 0.3)
                            : Colors.blue)
                      : Colors.blue.withValues(alpha: 0.1),
                  labelStyle: TextStyle(
                    color: isDark
                        ? (isHighContrast ? Colors.white : Colors.white)
                        : Colors.black,
                  ),
                ),
                const SizedBox(width: 4),
                // Status filter
                FilterChip(
                  label: Text(
                    _selectedStatusFilter,
                    style: TextStyle(
                      color: isDark
                          ? (isHighContrast ? Colors.white : Colors.white)
                          : Colors.black,
                    ),
                  ),
                  selected: _selectedStatusFilter != 'All Status',
                  onSelected: (selected) {
                    if (selected) {
                      // Show status filter dropdown
                      _showFilterDialog(
                        context,
                        'Filter by Status',
                        _statusFilters,
                        _selectedStatusFilter,
                        (value) {
                          setState(() {
                            _selectedStatusFilter = value;
                            _applyFilters();
                          });
                        },
                      );
                    } else {
                      setState(() {
                        _selectedStatusFilter = 'All Status';
                        _applyFilters();
                      });
                    }
                  },
                  backgroundColor: isDark
                      ? (isHighContrast
                            ? Colors.white.withValues(alpha: 0.05)
                            : Color(0xFF2A2D3A))
                      : Colors.grey.shade100,
                  selectedColor: isDark
                      ? (isHighContrast
                            ? Colors.blue.withValues(alpha: 0.3)
                            : Colors.blue)
                      : Colors.blue.withValues(alpha: 0.1),
                  labelStyle: TextStyle(
                    color: isDark
                        ? (isHighContrast ? Colors.white : Colors.white)
                        : Colors.black,
                  ),
                ),
              ],
            ),
            // Apply Filters button
            if (_selectedRoleFilter != 'All Roles' ||
                _selectedStatusFilter != 'All Status' ||
                _searchController.text.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // Reset all filters
                    setState(() {
                      _searchController.clear();
                      _selectedRoleFilter = 'All Roles';
                      _selectedStatusFilter = 'All Status';
                      _applyFilters();
                    });
                  },
                  child: Text(
                    'Clear Filters',
                    style: TextStyle(
                      color: DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.error,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog(
    BuildContext context,
    String title,
    List<String> options,
    String currentSelection,
    ValueChanged<String> onSelected,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: ListBody(
              children: options.map((option) {
                return ListTile(
                  title: Text(option),
                  selected: option == currentSelection,
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelected(option);
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showAddUserDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AddUserDialog(
          onUserAdded: () {
            Navigator.of(context).pop();
            _refreshUsers();
          },
          adminService: _adminService,
          token: _token!,
        );
      },
    );
  }

  void _showUserActionsDialog(dynamic user) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return UserActionsDialog(
          user: user,
          adminService: _adminService,
          token: _token!,
          onActionCompleted: () {
            Navigator.of(context).pop();
            _refreshUsers();
          },
          onViewEmployee: (employeeId) {
            setState(() {
              _selectedEmployeeId = employeeId;
            });
          },
        );
      },
    );
  }
}

// Dialog for adding a new user
class AddUserDialog extends StatefulWidget {
  final VoidCallback onUserAdded;
  final AdminService adminService;
  final String token;

  const AddUserDialog({
    super.key,
    required this.onUserAdded,
    required this.adminService,
    required this.token,
  });

  @override
  State<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _organizationController = TextEditingController();
  String _selectedRole = 'EMPLOYEE';
  String _selectedAccountType = 'organization';
  bool _isLoading = false;
  String? _errorMessage;

  final List<String> _roles = ['EMPLOYEE', 'MANAGER', 'ADMIN'];
  final List<String> _accountTypes = ['solo', 'organization'];

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _organizationController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.adminService.createUser(
        widget.token,
        _emailController.text,
        _passwordController.text,
        _fullNameController.text,
        accountType: _selectedAccountType,
        organizationName: _selectedAccountType == 'organization'
            ? _organizationController.text
            : null,
        role: _selectedRole,
      );

      if (!mounted) return;
      widget.onUserAdded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context)
        .isHighContrast;

    return AlertDialog(
      title: const Text('Add New User'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(
                    Icons.email,
                    color: isDark
                        ? (isHighContrast ? Colors.white : Color(0xFFA5A7AE))
                        : Colors.grey,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an email';
                  }
                  if (!value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(
                    Icons.lock,
                    color: isDark
                        ? (isHighContrast ? Colors.white : Color(0xFFA5A7AE))
                        : Colors.grey,
                  ),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fullNameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(
                    Icons.person,
                    color: isDark
                        ? (isHighContrast ? Colors.white : Color(0xFFA5A7AE))
                        : Colors.grey,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a full name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedAccountType,
                decoration: InputDecoration(
                  labelText: 'Account Type',
                  prefixIcon: Icon(
                    Icons.account_circle,
                    color: isDark
                        ? (isHighContrast ? Colors.white : Color(0xFFA5A7AE))
                        : Colors.grey,
                  ),
                ),
                items: _accountTypes.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedAccountType = newValue!;
                    // Clear organization field if switching to solo
                    if (newValue == 'solo') {
                      _organizationController.clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_selectedAccountType == 'organization')
                TextFormField(
                  controller: _organizationController,
                  decoration: InputDecoration(
                    labelText: 'Organization Name',
                    prefixIcon: Icon(
                      Icons.business,
                      color: isDark
                          ? (isHighContrast ? Colors.white : Color(0xFFA5A7AE))
                          : Colors.grey,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(
                    Icons.person_pin,
                    color: isDark
                        ? (isHighContrast ? Colors.white : Color(0xFFA5A7AE))
                        : Colors.grey,
                  ),
                ),
                items: _roles.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedRole = newValue!;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitForm,
          style: ElevatedButton.styleFrom(
            backgroundColor: DesignSystem.getSemanticColor(
              context,
              SemanticColor.success,
            ),
          ),
          child: const Text('Add User'),
        ),
      ],
    );
  }
}

// Dialog for user actions (edit, change role, activate/deactivate, reset password, delete) with card-based layout
class UserActionsDialog extends StatefulWidget {
  final dynamic user;
  final AdminService adminService;
  final String token;
  final VoidCallback onActionCompleted;
  final ValueChanged<String> onViewEmployee;

  const UserActionsDialog({
    super.key,
    required this.user,
    required this.adminService,
    required this.token,
    required this.onActionCompleted,
    required this.onViewEmployee,
  });

  @override
  State<UserActionsDialog> createState() => _UserActionsDialogState();
}

class _UserActionsDialogState extends State<UserActionsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isProcessing = false;
  String? _errorMessage;

  // Role change state
  late String _selectedNewRole;
  bool _isEditingInfo = false;
  late TextEditingController _fullNameController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _selectedNewRole = widget.user['role'] ?? 'EMPLOYEE';
    _fullNameController = TextEditingController(
      text: widget.user['full_name'] ?? '',
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _changeRole() async {
    if (_selectedNewRole == widget.user['role']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected role is already current role')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Role Change'),
        content: Text(
          'Are you sure you want to change this user\'s role to $_selectedNewRole?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      await widget.adminService.updateUser(
        widget.token,
        widget.user['id'].toString(),
        role: _selectedNewRole,
      );

      if (!mounted) return;
      widget.onActionCompleted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _updateUserInfo() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      await widget.adminService.updateUser(
        widget.token,
        widget.user['id'].toString(),
        fullName: _fullNameController.text,
      );

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _isEditingInfo = false;
      });
      widget.onActionCompleted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _changeStatus(bool isActive) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isActive ? 'Activate Account' : 'Deactivate Account'),
        content: Text(
          'Are you sure you want to ${isActive ? 'activate' : 'deactivate'} this user account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Colors.green : Colors.red,
            ),
            child: Text(isActive ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      await widget.adminService.changeUserStatus(
        widget.token,
        widget.user['id'].toString(),
        isActive,
      );

      if (!mounted) return;
      widget.onActionCompleted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _resetPassword() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.adminService.resetUserPassword(
        widget.token,
        widget.user['id'].toString(),
      );

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });

      final String? tempPassword = response['temporary_password'];
      if (tempPassword != null && tempPassword.isNotEmpty) {
        _showResetPasswordSuccessDialog(tempPassword);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password reset successfully')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reset password: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showResetPasswordSuccessDialog(String tempPassword) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context, listen: false).isHighContrast;
    final String name = widget.user['full_name'] ?? 'User';
    final String email = widget.user['email'] ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        bool copied = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: isDark
                  ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF1B1D24))
                  : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 28),
                  const SizedBox(width: 12),
                  const Text('Password Reset Successful'),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Temporary password generated for $name ($email):',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2A2D3A) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? const Color(0xFF404452) : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                tempPassword,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                copied ? Icons.check : Icons.copy,
                                color: copied ? Colors.green : Colors.blue,
                              ),
                              tooltip: 'Copy Temporary Password',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: tempPassword));
                                setStateDialog(() {
                                  copied = true;
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Temporary password copied to clipboard'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.amber.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'The user must change their password at next login. This password will not be shown again.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    widget.onActionCompleted();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteUser() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: const Text(
          'Are you sure you want to permanently delete this user? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await widget.adminService.deleteUser(
        widget.token,
        widget.user['id'].toString(),
      );

      if (!mounted) return;
      widget.onActionCompleted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context)
        .isHighContrast;
    final String name = widget.user['full_name'] ?? 'Unknown User';
    final String email = widget.user['email'] ?? 'N/A';
    final String role = widget.user['role'] ?? 'EMPLOYEE';
    final String approvalStatus = widget.user['approval_status'] ?? 'PENDING';
    final bool isActive = widget.user['is_active'] ?? false;
    final String createdAt = widget.user['created_at'] ?? 'N/A';
    final String orgName = widget.user['organization_name'] ?? 'N/A';

    Color statusColor = Colors.orange;
    if (approvalStatus == 'APPROVED') {
      statusColor = Colors.green;
    } else if (approvalStatus == 'REJECTED') {
      statusColor = Colors.red;
    }

    return Dialog(
      backgroundColor: isDark
          ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF1B1D24))
          : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 780,
        constraints: const BoxConstraints(maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.blue,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage User: $name',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              email,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                approvalStatus,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 2. Navigation tabs
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.grey.shade200,
                  ),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.blue,
                unselectedLabelColor: isDark ? Colors.white60 : Colors.grey.shade600,
                indicatorColor: Colors.blue,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined, size: 18)),
                  Tab(text: 'Role & Access', icon: Icon(Icons.security, size: 18)),
                  Tab(text: 'Status', icon: Icon(Icons.check_circle_outline, size: 18)),
                  Tab(text: 'Activity Log', icon: Icon(Icons.history, size: 18)),
                ],
              ),
            ),

            // Tab Views Content Area
            Expanded(
              child: _isProcessing
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        // Overview Tab
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_errorMessage != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.red.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              // 3. User Information Card
                              _buildCard(
                                isDark: isDark,
                                title: 'User Information',
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (_isEditingInfo) ...[
                                                TextField(
                                                  controller: _fullNameController,
                                                  decoration: const InputDecoration(
                                                    labelText: 'Full Name',
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    ElevatedButton(
                                                      onPressed: _updateUserInfo,
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: Colors.blue,
                                                      ),
                                                      child: const Text('Save'),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    TextButton(
                                                      onPressed: () => setState(
                                                        () => _isEditingInfo = false,
                                                      ),
                                                      child: const Text('Cancel'),
                                                    ),
                                                  ],
                                                ),
                                              ] else ...[
                                                _infoRow('Full Name', name, isDark),
                                                const SizedBox(height: 8),
                                                _infoRow('Email', email, isDark),
                                                const SizedBox(height: 8),
                                                _infoRow('Current Role', role, isDark),
                                                const SizedBox(height: 8),
                                                _infoRow('Account Status', approvalStatus, isDark),
                                                const SizedBox(height: 8),
                                                _infoRow('Organization', orgName, isDark),
                                                const SizedBox(height: 8),
                                                _infoRow('Date Created', createdAt.length > 10 ? createdAt.substring(0, 10) : createdAt, isDark),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Column(
                                          children: [
                                            Container(
                                              width: 64,
                                              height: 64,
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withValues(alpha: 0.15),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.person_outline,
                                                color: Colors.blue,
                                                size: 32,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            if (!_isEditingInfo)
                                              OutlinedButton.icon(
                                                onPressed: () => setState(
                                                  () => _isEditingInfo = true,
                                                ),
                                                icon: const Icon(Icons.edit, size: 14),
                                                label: const Text('Edit User Info'),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 4. Change Role Card
                              _buildCard(
                                isDark: isDark,
                                title: 'Change Role',
                                icon: Icons.security,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Update the security role assigned to this user within the organization.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Row(
                                      children: [
                                        DropdownButton<String>(
                                          value: _selectedNewRole,
                                          dropdownColor: isDark
                                              ? const Color(0xFF2A2D3A)
                                              : Colors.white,
                                          items: ['EMPLOYEE', 'MANAGER', 'ADMIN']
                                              .map(
                                                (r) => DropdownMenuItem(
                                                  value: r,
                                                  child: Text(
                                                    r,
                                                    style: TextStyle(
                                                      color: isDark
                                                          ? Colors.white
                                                          : Colors.black87,
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(
                                                () => _selectedNewRole = val,
                                              );
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 12),
                                        ElevatedButton(
                                          onPressed: _changeRole,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue,
                                          ),
                                          child: const Text('Update Role'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 5. Account Actions Card
                              _buildCard(
                                isDark: isDark,
                                title: 'Account Actions',
                                icon: Icons.bolt,
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _isProcessing ? null : _resetPassword,
                                      icon: const Icon(Icons.lock_reset, size: 16),
                                      label: const Text('Reset Password'),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        widget.onViewEmployee(
                                          widget.user['id'].toString(),
                                        );
                                      },
                                      icon: const Icon(Icons.visibility, size: 16),
                                      label: const Text('View Employee'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 6. Destructive Actions Card
                              _buildCard(
                                isDark: isDark,
                                title: 'Destructive Actions',
                                icon: Icons.warning_amber_rounded,
                                iconColor: Colors.red,
                                borderColor: Colors.red.withValues(alpha: 0.3),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Actions in this section can have serious consequences for user access and data retention.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: () => _changeStatus(!isActive),
                                          icon: Icon(
                                            isActive ? Icons.block : Icons.check_circle,
                                            size: 16,
                                          ),
                                          label: Text(
                                            isActive
                                                ? 'Deactivate Account'
                                                : 'Activate Account',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isActive
                                                ? Colors.red
                                                : Colors.green,
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _deleteUser,
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 16,
                                            color: Colors.red,
                                          ),
                                          label: const Text(
                                            'Delete User',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(
                                              color: Colors.red,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Role & Access Tab
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Role & Access Control',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Current Role: $role',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Organization Membership: $orgName',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Permissions summary:\n• ADMIN: Full system administration, user management, audit logs.\n• MANAGER: Team overview, work sessions, employee oversight.\n• EMPLOYEE: Personal work sessions, break coaching, profile management.',
                                style: TextStyle(fontSize: 13, height: 1.5),
                              ),
                            ],
                          ),
                        ),

                        // Status Tab
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Account Status & Presence',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _infoRow('Approval Status', approvalStatus, isDark),
                              const SizedBox(height: 8),
                              _infoRow('Active Status', isActive ? 'Active' : 'Inactive', isDark),
                              const SizedBox(height: 8),
                              _infoRow('Created At', createdAt, isDark),
                            ],
                          ),
                        ),

                        // Activity Log Tab
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'User Activity & Audit History',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Recent activity and audit events associated with user $email.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Expanded(
                                child: Center(
                                  child: Text(
                                    'No recent suspicious activity or audit flags recorded.',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),

            // 7. Footer Close button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required bool isDark,
    required String title,
    required Widget child,
    IconData? icon,
    Color? iconColor,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222531) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor ??
              (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.shade300),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: iconColor ?? Colors.blue),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white60 : Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }
}
