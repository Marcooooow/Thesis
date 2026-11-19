import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/features/admin/screens/admin_dashboard.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  Widget build(BuildContext context) {
    return const AdminDashboardScreen();
  }
}

// Content widget for use within AppShell
class AdminScreenContent extends StatefulWidget {
  const AdminScreenContent({super.key});

  @override
  State<AdminScreenContent> createState() => _AdminScreenContentState();
}

class _AdminScreenContentState extends State<AdminScreenContent>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  Set<String> _approvingIds = {};
  List<dynamic> _pendingUsers = [];
  List<dynamic> _auditLogs = [];
  String? _errorMessage;
  int _selectedIndex = 0;
  bool _auditLogsLoading = false;
  String? _auditLogsError;
  int _auditLogsPage = 1;
  final int _auditLogsLimit = 25;
  bool _hasMoreAuditLogs = true;
  late TabController _tabController;

  // Audit log filters
  String? _selectedActionType;
  String? _selectedUserId;
  DateTime? _startDate;
  DateTime? _endDate;
  String _searchText = '';
  List<dynamic> _actionTypes = [];
  List<dynamic> _users = [];
  bool _isLoadingFilters = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedIndex = 0;
    _checkRoleAndLoadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkRoleAndLoadData() async {
    try {
      final token = await _apiService.getToken();
      if (token == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'No authentication token';
        });
        return;
      }

      final userData = await _apiService.getMe(token);
      final role = userData['role'];
      if (role != 'ADMIN') {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Access denied: Admin privileges required';
        });
        return;
      }

      if (_selectedIndex == 0) {
        await _loadPendingUsers(token);
      } else {
        await _loadAuditFilters(token);
        await _loadAuditLogs(token, refresh: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _loadAuditFilters(String token) async {
    try {
      setState(() {
        _isLoadingFilters = true;
      });

      // In a real implementation, we would call API endpoints to get filter options
      // For now, we'll simulate with some common action types and users
      // TODO: Replace with actual API calls when available
      _actionTypes = [
        {'id': 'USER_CREATED', 'name': 'User Created'},
        {'id': 'USER_APPROVED', 'name': 'User Approved'},
        {'id': 'USER_REJECTED', 'name': 'User Rejected'},
        {'id': 'WORK_SESSION_STARTED', 'name': 'Work Session Started'},
        {'id': 'WORK_SESSION_ENDED', 'name': 'Work Session Ended'},
        {'id': 'TASK_CREATED', 'name': 'Task Created'},
        {'id': 'BREAK_STARTED', 'name': 'Break Started'},
        {'id': 'BREAK_ENDED', 'name': 'Break Ended'},
        {'id': 'LOGIN', 'name': 'Login'},
        {'id': 'LOGOUT', 'name': 'Logout'},
      ];

      // Get some users for the filter dropdown
      final pendingUsers = await _apiService.getPendingUsers(token);
      final users = pendingUsers
          .map(
            (user) => ({
              'id': user['id'].toString(),
              'name': '${user['full_name']} (${user['email']})',
            }),
          )
          .toList();

      _users = users;

      if (!mounted) return;
      setState(() {
        _isLoadingFilters = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingFilters = false;
      });
    }
  }

  Future<void> _loadPendingUsers(String token) async {
    try {
      final pendingUsers = await _apiService.getPendingUsers(token);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _pendingUsers = pendingUsers;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _loadAuditLogs(String token, {bool refresh = false}) async {
    if (refresh) {
      _auditLogsPage = 1;
      _auditLogs.clear();
      _hasMoreAuditLogs = true;
    }

    if (!_hasMoreAuditLogs) return;

    try {
      setState(() {
        if (_auditLogs.isEmpty) {
          _auditLogsLoading = true;
        }
      });

      // Build query parameters for filtering
      final queryParams = <String, String>{};
      if (_selectedActionType != null && _selectedActionType!.isNotEmpty) {
        queryParams['action_type'] = _selectedActionType!;
      }
      if (_selectedUserId != null && _selectedUserId!.isNotEmpty) {
        queryParams['user_id'] = _selectedUserId!;
      }
      if (_startDate != null) {
        queryParams['start_date'] = _startDate!.toIso8601String();
      }
      if (_endDate != null) {
        queryParams['end_date'] = _endDate!.toIso8601String();
      }
      if (_searchText.isNotEmpty) {
        queryParams['search'] = _searchText;
      }

      final auditLogs = await _apiService.getAuditLogs(
        token,
        page: _auditLogsPage,
        limit: _auditLogsLimit,
        actionType: _selectedActionType,
        userId: _selectedUserId != null && _selectedUserId!.isNotEmpty
            ? _selectedUserId
            : null,
        startDate: _startDate,
        endDate: _endDate,
      );

      if (!mounted) return;

      setState(() {
        _auditLogsLoading = false;
        if (refresh) {
          _auditLogs = auditLogs;
        } else {
          _auditLogs.addAll(auditLogs);
        }
        _auditLogsError = null;

        if (auditLogs.length < _auditLogsLimit) {
          _hasMoreAuditLogs = false;
        } else {
          _auditLogsPage++;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _auditLogsLoading = false;
        _auditLogsError = e.toString();
      });
    }
  }

  Future<void> _approveUser(String userId) async {
    if (_approvingIds.contains(userId)) return;
    setState(() => _approvingIds.add(userId));
    try {
      final token = await _apiService.getToken();
      if (token == null) {
        setState(() => _approvingIds.remove(userId));
        return;
      }
      await _apiService.approveUser(token, userId);
      if (mounted) {
        setState(() {
          _pendingUsers.removeWhere((u) => u['id'] == userId);
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User approved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to approve user: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _approvingIds.remove(userId));
      }
    }
  }

  Future<void> _rejectUser(String userId) async {
    try {
      final token = await _apiService.getToken();
      if (token == null) return;

      await _apiService.rejectUser(token, userId);
      await _loadPendingUsers(token);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to reject user: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context)
        .isHighContrast;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isDark
            ? (isHighContrast
                  ? const Color(0xFF0D0D0D)
                  : const Color(0xFF1A1A1A))
            : Colors.white,
        appBar: AppBar(
          title: const Text('Admin Panel'),
          backgroundColor: isDark
              ? (isHighContrast
                    ? const Color(0xFF0D0D0D)
                    : const Color(0xFF1A1A1A))
              : Colors.white,
          foregroundColor: isDark
              ? (isHighContrast ? Colors.white : Color(0xFFF2F2F2))
              : Colors.black,
          elevation: 0,
          bottom: TabBar(
            onTap: (index) async {
              setState(() {
                _selectedIndex = index;
              });
              if (index == 1 && _auditLogs.isEmpty) {
                final token = await _apiService.getToken();
                if (token != null) {
                  await _loadAuditLogs(token);
                }
              }
            },
            labelColor: isDark
                ? (isHighContrast ? Colors.white : Color(0xFFF2F2F2))
                : Colors.black,
            unselectedLabelColor: isDark
                ? (isHighContrast
                      ? Colors.white.withValues(alpha: 0.5)
                      : Color(0xFFA5A7AE))
                : Colors.grey.shade600,
            indicatorColor: DesignSystem.getSemanticColor(
              context,
              SemanticColor.primary,
            ),
            tabs: const [
              Tab(text: 'Pending Users'),
              Tab(text: 'Audit Logs'),
            ],
          ),
        ),
        body: _selectedIndex == 0 ? _buildPendingUsers() : _buildAuditLogs(),
      ),
    );
  }

  Widget _buildPendingUsers() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Error: $_errorMessage', style: TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _checkRoleAndLoadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_pendingUsers.isEmpty) {
      return const Center(child: Text('No pending users.'));
    }

    return ListView.builder(
      itemCount: _pendingUsers.length,
      itemBuilder: (context, index) {
        final user = _pendingUsers[index];
        return _buildPendingUserCard(user);
      },
    );
  }

  Widget _buildAuditLogs() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context)
        .isHighContrast;
    // Filter controls
    return Column(
      children: [
        // Filter controls card
        if (_isLoadingFilters || _actionTypes.isEmpty || _users.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: LinearProgressIndicator(),
          )
        else
          Container(
            margin: const EdgeInsets.all(16.0),
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: isDark
                  ? (isHighContrast
                        ? const Color(0xFF0D0D0D)
                        : const Color(0xFF1B1D24))
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filters',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? (isHighContrast ? Colors.white : Colors.white)
                        : Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    // Action Type Dropdown
                    _buildFilterDropdown(
                      label: 'Action Type',
                      value: _selectedActionType,
                      items: _actionTypes
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['id'] as String,
                              child: Text(item['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedActionType = value;
                          // Reset pagination when filters change
                          _auditLogsPage = 1;
                          _auditLogs.clear();
                          _hasMoreAuditLogs = true;
                        });
                      },
                    ),
                    // User Dropdown
                    _buildFilterDropdown(
                      label: 'User',
                      value: _selectedUserId,
                      items: _users
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['id'] as String,
                              child: Text(item['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedUserId = value;
                          // Reset pagination when filters change
                          _auditLogsPage = 1;
                          _auditLogs.clear();
                          _hasMoreAuditLogs = true;
                        });
                      },
                    ),
                    // Date Range
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Date Range',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDateField(
                                label: 'From',
                                date: _startDate,
                                onDateSelected: (date) {
                                  setState(() {
                                    _startDate = date;
                                    // Reset pagination when filters change
                                    _auditLogsPage = 1;
                                    _auditLogs.clear();
                                    _hasMoreAuditLogs = true;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildDateField(
                                label: 'To',
                                date: _endDate,
                                onDateSelected: (date) {
                                  setState(() {
                                    _endDate = date;
                                    // Reset pagination when filters change
                                    _auditLogsPage = 1;
                                    _auditLogs.clear();
                                    _hasMoreAuditLogs = true;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Apply Filters Button
                    ElevatedButton(
                      onPressed: () async {
                        final token = await _apiService.getToken();
                        if (token != null) {
                          await _loadAuditLogs(token, refresh: true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DesignSystem.getSemanticColor(
                          context,
                          SemanticColor.primary,
                        ),
                      ),
                      child: const Text('Apply Filters'),
                    ),
                    // Clear Filters Button
                    TextButton(
                      onPressed: () async {
                        setState(() {
                          _selectedActionType = null;
                          _selectedUserId = null;
                          _startDate = null;
                          _endDate = null;
                          _searchText = '';
                          // Reset pagination when filters change
                          _auditLogsPage = 1;
                          _auditLogs.clear();
                          _hasMoreAuditLogs = true;
                        });
                        final token = await _apiService.getToken();
                        if (token != null) {
                          await _loadAuditLogs(token, refresh: true);
                        }
                      },
                      child: const Text('Clear Filters'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Search Field
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Search',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search audit logs...',
                          border: OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchText = value;
                            // Reset pagination when filters change
                            _auditLogsPage = 1;
                            _auditLogs.clear();
                            _hasMoreAuditLogs = true;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        // Audit logs list
        Expanded(child: _buildAuditLogsList()),
      ],
    );
  }

  Widget _buildAuditLogsList() {
    if (_auditLogsLoading && _auditLogs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_auditLogsError != null && _auditLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Error: $_auditLogsError',
              style: TextStyle(color: Colors.red),
            ),
            ElevatedButton(
              onPressed: () async {
                final token = await _apiService.getToken();
                if (token != null) {
                  await _loadAuditLogs(token, refresh: true);
                }
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_auditLogs.isEmpty && !_auditLogsLoading) {
      return const Center(child: Text('No audit logs found.'));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollNotification) {
        if (_auditLogsLoading ||
            !_hasMoreAuditLogs ||
            scrollNotification.metrics.pixels <
                scrollNotification.metrics.maxScrollExtent * 0.8) {
          return false;
        }
        _loadMoreAuditLogs();
        return true;
      },
      child: ListView.builder(
        itemCount: _auditLogs.length + (_hasMoreAuditLogs ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _auditLogs.length) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: _auditLogsLoading
                    ? const CircularProgressIndicator()
                    : const Text('No more logs'),
              ),
            );
          }

          final log = _auditLogs[index];
          return _buildAuditLogCard(log);
        },
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context)
        .isHighContrast;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<T>(
            initialValue: value,
            items: items,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Select $label',
              border: OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            dropdownColor: isDark
                ? (isHighContrast
                      ? const Color(0xFF0D0D0D)
                      : const Color(0xFF1B1D24))
                : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required void Function(DateTime?) onDateSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 120,
          child: TextField(
            readOnly: true,
            decoration: InputDecoration(
              hintText: date != null
                  ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
                  : 'Select date',
              border: OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              suffixIcon: const Icon(Icons.calendar_today),
            ),
            onTap: () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: date ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null && picked != date) {
                onDateSelected(picked);
              }
            },
          ),
        ),
      ],
    );
  }

  void _loadMoreAuditLogs() async {
    final token = await _apiService.getToken();
    if (token != null) {
      await _loadAuditLogs(token);
    }
  }

  Widget _buildPendingUserCard(dynamic user) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context)
        .isHighContrast;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark
          ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF1B1D24))
          : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${user['full_name'] ?? 'N/A'}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? (isHighContrast ? Colors.white : Color(0xFFF2F2F2))
                    : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user['email'] ?? 'N/A',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : Color(0xFFA5A7AE))
                    : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Job Role: ${user['job_role'] ?? 'N/A'}',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : Color(0xFFA5A7AE))
                    : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Registered: ${user['created_at'] ?? 'N/A'}',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.5)
                          : Color(0xFFA5A7AE))
                    : Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _approvingIds.contains(user['id']) ? null : () => _approveUser(user['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.success,
                      ),
                    ),
                    child: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _rejectUser(user['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.error,
                      ),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditLogCard(dynamic log) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context)
        .isHighContrast;

    String formattedDate = 'Unknown date';
    if (log['created_at'] != null) {
      try {
        final dateTime = DateTime.parse(log['created_at']);
        formattedDate =
            '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
      } catch (e) {
        formattedDate = log['created_at'].toString();
      }
    }

    String detailsText = 'No additional details';
    if (log['action_details'] != null &&
        log['action_details'] is Map &&
        log['action_details'].isNotEmpty) {
      try {
        final details = log['action_details'] as Map;
        final detailsList = details.entries.map((entry) {
          return '${entry.key}: ${entry.value}';
        }).toList();
        detailsText = detailsList.join(', ');
      } catch (e) {
        detailsText = log['action_details'].toString();
      }
    }

    final String userName =
        log['user_full_name'] ?? log['user_email'] ?? 'System';
    final String userEmail = log['user_email'] ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark
          ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF1B1D24))
          : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    log['action_type'] ?? 'Unknown Action',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? (isHighContrast ? Colors.white : Color(0xFFF2F2F2))
                          : Colors.black,
                    ),
                  ),
                ),
                Text(
                  formattedDate,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? (isHighContrast
                              ? Colors.white.withValues(alpha: 0.5)
                              : Color(0xFFA5A7AE))
                        : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'User: $userName',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : Color(0xFFA5A7AE))
                    : Colors.grey.shade600,
              ),
            ),
            if (userEmail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Email: $userEmail',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? (isHighContrast
                              ? Colors.white.withValues(alpha: 0.5)
                              : Color(0xFFA5A7AE))
                        : Colors.grey.shade500,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Details: $detailsText',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : Color(0xFFA5A7AE))
                    : Colors.grey.shade600,
              ),
            ),
            if (log['ip_address'] != null && log['ip_address'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'IP: ${log['ip_address']}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? (isHighContrast
                              ? Colors.white.withValues(alpha: 0.4)
                              : Color(0xFFA5A7AE).withValues(alpha: 0.6))
                        : Colors.grey.shade400,
                  ),
                ),
              ),
            if (log['user_agent'] != null && log['user_agent'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Agent: ${log['user_agent']}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark
                        ? (isHighContrast
                              ? Colors.white.withValues(alpha: 0.3)
                              : Color(0xFFA5A7AE).withValues(alpha: 0.5))
                        : Colors.grey.shade300,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
