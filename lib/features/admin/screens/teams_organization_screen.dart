import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../team/widgets/create_team_dialog.dart';
import 'team_details_screen.dart';

class TeamsOrganizationScreen extends StatefulWidget {
  const TeamsOrganizationScreen({super.key});

  @override
  State<TeamsOrganizationScreen> createState() => _TeamsOrganizationScreenState();
}

class _TeamsOrganizationScreenState extends State<TeamsOrganizationScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  int _employeesCount = 0;
  int _managersCount = 0;
  List<dynamic> _teams = [];
  int _unassignedCount = 0;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    if (token != null) {
      try {
        // Load organization overview (employees, managers, pending)
        final userCounts = await _apiService.getMapWithAuth(
          '/admin/user-counts',
          token,
        );
        if (userCounts != null && mounted) {
          setState(() {
            _employeesCount = userCounts['employees'] ?? 0;
            _managersCount = userCounts['managers'] ?? 0;
          });
        }

        // Load teams (for admin, /teams/my-teams returns all teams)
        final teams = await _apiService.getListWithAuth(
          '/teams/my-teams',
          token,
        );
        setState(() {
          _teams = teams;
          // Calculate unassigned: total employees - sum of team members
          final totalAssigned = teams.fold(
            0,
            (previous, element) => previous + ((element['member_count'] ?? 0) as int),
          );
          _unassignedCount = (_employeesCount - totalAssigned).clamp(0, _employeesCount);
        });

        // Load user role
        final userData = await _apiService.getMe(token);
        setState(() {
          _userRole = userData['role'];
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
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

  bool _hasError = false;

  Future<void> _refreshData() async {
    await _loadInitialData();
  }

  void _showCreateTeamDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateTeamDialog(
        onTeamCreated: () {
          Navigator.of(context).pop();
          _refreshData();
        },
      ),
    );
  }

  void _viewTeamDetails(String teamId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamDetailsScreen(teamId: teamId),
      ),
    );
  }

  void _editTeam(String teamId) {
    final team = _teams.firstWhere((t) => t['id'].toString() == teamId, orElse: () => null);
    if (team == null) return;

    final nameController = TextEditingController(text: team['name'] ?? '');
    final descriptionController = TextEditingController(text: team['description'] ?? '');
    bool isLoading = false;
    String? error;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Team'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Team Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Error: $error',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(context).pop(),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                setState(() {
                  isLoading = true;
                  error = null;
                });
                try {
                  final token = await _apiService.getToken();
                  if (token == null) {
                    throw Exception('No token available');
                  }
                  await _apiService.patchWithAuth(
                    '/teams/$teamId',
                    token,
                    {
                      'name': nameController.text.trim(),
                      'description': descriptionController.text.trim(),
                    },
                  );
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Team updated successfully')),
                  );
                  await _refreshData();
                } catch (e) {
                  if (!mounted) return;
                  setState(() {
                    isLoading = false;
                    error = e.toString();
                  });
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _changeManager(String teamId) {
    final team = _teams.firstWhere((t) => t['id'].toString() == teamId, orElse: () => null);
    if (team == null) return;

    final emailController = TextEditingController();
    bool isLoading = false;
    String? error;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Change Team Manager'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Manager Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Error: $error',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(context).pop(),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Cancel'),
              ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                setState(() {
                  isLoading = true;
                  error = null;
                });
                try {
                  final token = await _apiService.getToken();
                  if (token == null) {
                    throw Exception('No token available');
                  }
                  // Resolve email to manager ID via search endpoint
                  final q = emailController.text.trim().toLowerCase();
                  if (q.isEmpty) throw Exception('Enter a manager email');
                  final searchResults = await _apiService.getListWithAuth(
                    '/teams/$teamId/managers/search?q=$q',
                    token,
                  );
                  if (searchResults == null || searchResults.isEmpty) {
                    throw Exception('Manager not found');
                  }
                  final List<dynamic> matches = searchResults;
                  dynamic selected;
                  if (matches.length == 1) {
                    selected = matches[0];
                  } else {
                    selected = matches.cast<dynamic>().firstWhere(
                      (m) => (m['email'] ?? '').toString().toLowerCase() == q,
                      orElse: () => null,
                    );
                  }
                  if (selected == null) {
                    throw Exception('Ambiguous or no matching manager; use exact email');
                  }
                  final managerUserId = selected['id'];
                  if (managerUserId == null || managerUserId.toString().isEmpty) {
                    throw Exception('Manager search returned invalid ID');
                  }
                  await _apiService.patchWithAuth(
                    '/teams/$teamId/manager',
                    token,
                    {
                      'manager_user_id': managerUserId.toString(),
                    },
                  );
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Team manager changed successfully')),
                  );
                  await _refreshData();
                } catch (e) {
                  if (!mounted) return;
                  setState(() {
                    isLoading = false;
                    error = e.toString();
                  });
                }
              },
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }

  void _manageMembers(String teamId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamDetailsScreen(
          teamId: teamId,
          initialTab: 1,
        ),
      ),
    );
  }

  void _deleteTeam(String teamId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Team'),
        content: const Text('Are you sure you want to delete this team? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                final token = await _apiService.getToken();
                if (token == null) {
                  throw Exception('No token available');
                }
                await _apiService.deleteWithAuth(
                  '/teams/$teamId',
                  token,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Team deleted successfully')),
                );
                await _refreshData();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete team: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
          ? _buildErrorView(isDark, isHighContrast)
          : _buildTeamsOrganizationView(
              context, isDark, isHighContrast, isDesktop),
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
              'Error Loading Teams & Organization',
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
              onPressed: _refreshData,
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

  Widget _buildTeamsOrganizationView(
      BuildContext context,
      bool isDark,
      bool isHighContrast,
      bool isDesktop) {
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
                    const Icon(Icons.group, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Teams & Organization',
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
                // Create Team Button
                if (_userRole == 'ADMIN' || _userRole == 'MANAGER')
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _showCreateTeamDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Create Team'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DesignSystem.getSemanticColor(
                          context,
                          SemanticColor.success,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // Organization Overview Cards
                _buildOrganizationOverviewCards(context),
                const SizedBox(height: 24),
                // Teams Table
                _buildTeamsTable(context, isDark, isHighContrast),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildOrganizationOverviewCards(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DesignSystem.statCard(
            context: context,
            label: 'Employees',
            value: _employeesCount.toString(),
            icon: Icons.business,
            color: Colors.blue,
            description: 'Approved employees in organization',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DesignSystem.statCard(
            context: context,
            label: 'Managers',
            value: _managersCount.toString(),
            icon: Icons.manage_accounts,
            color: Colors.green,
            description: 'Approved managers in organization',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DesignSystem.statCard(
            context: context,
            label: 'Unassigned Employees',
            value: _unassignedCount.toString(),
            icon: Icons.person_outline,
            color: Colors.orange,
            description: 'Employees not assigned to any team',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DesignSystem.statCard(
            context: context,
            label: 'Teams',
            value: _teams.length.toString(),
            icon: Icons.group,
            color: Colors.purple,
            description: 'Total teams in organization',
          ),
        ),
      ],
    );
  }

  Widget _buildTeamsTable(
      BuildContext context,
      bool isDark,
      bool isHighContrast) {
    if (_teams.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 48,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.5)
                        : Color(0xFFA5A7AE))
                  : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No teams found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a team to get started',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Color(0xFFA5A7AE) : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return DesignSystem.premiumCard(
      context: context,
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2C33) : Colors.grey.shade200,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'TEAM',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'MANAGER',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'MEMBERS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'STATUS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'ACTIONS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Table rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _teams.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: isDark ? const Color(0xFF30323A) : Colors.grey.shade300,
            ),
            itemBuilder: (context, index) {
              final team = _teams[index];
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        team['name'] ?? 'N/A',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        team['manager_name'] ?? 'No manager',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        '${team['member_count'] ?? 0}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (team['is_active'] ?? false)
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          (team['is_active'] ?? false) ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: (team['is_active'] ?? false)
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: PopupMenuButton<String>(
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'view',
                            child: const Row(
                              children: [
                                Icon(Icons.visibility, size: 18),
                                SizedBox(width: 8),
                                Text('View Team'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'edit',
                            child: const Row(
                              children: [
                                Icon(Icons.edit, size: 18),
                                SizedBox(width: 8),
                                Text('Edit Team'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'change_manager',
                            child: const Row(
                              children: [
                                Icon(Icons.person_add, size: 18),
                                SizedBox(width: 8),
                                Text('Change Manager'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'manage_members',
                            child: const Row(
                              children: [
                                Icon(Icons.group_add, size: 18),
                                SizedBox(width: 8),
                                Text('Manage Members'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: const Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete Team'),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) {
                          final teamId = team['id'].toString();
                          switch (value) {
                            case 'view':
                              _viewTeamDetails(teamId);
                              break;
                            case 'edit':
                              _editTeam(teamId);
                              break;
                            case 'change_manager':
                              _changeManager(teamId);
                              break;
                            case 'manage_members':
                              _manageMembers(teamId);
                              break;
                            case 'delete':
                              _deleteTeam(teamId);
                              break;
                          }
                        },
                        icon: Icon(Icons.more_vert, size: 18),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}