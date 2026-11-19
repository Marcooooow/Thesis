import 'package:flutter/material.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/dashboard/widgets/greeting_section.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/features/analytics/widgets/focus_idle_line_chart.dart';
import 'package:intellibreak/providers/team_provider.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final ApiService _apiService = ApiService();
  String? _userName;

  // Loading phases for progressive loading
  bool _phase3Loaded = false;

  // Phase 1 - Essential data
  int _employeesCount = 0;
  int _managersCount = 0;
  int _pendingCount = 0;
  int _activeSessionsCount = 0;
  int _activeBreaksCount = 0;

  // Phase 2 - Secondary data
  List<dynamic> _pendingUsers = [];

  // Phase 3 - Detailed analytics
  Map<String, double> _todayFocusRatio = {
    'activeFocus': 0.0,
    'idle': 0.0,
    'nonActive': 0.0,
  };
  List<dynamic> _weeklyFocusIdle = [];
  double _focusRate = 0.0;
  List<dynamic> _weeklyWorkHours = [];

  // Audit logs (loaded on demand)
  List<dynamic> _auditLogs = [];
  int _auditLogsPage = 1;
  final int _auditLogsLimit = 20;
  bool _hasMoreAuditLogs = true;
  bool _auditLogsLoading = false;
  String? _auditLogsError;

  // Phase 1/2 loading flags
  bool _isLoadingOverview = false;
  bool _isLoadingPending = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final token = await _apiService.getToken();
      if (token == null) {
        if (!mounted) return;
        setState(() {
          _userName = null;
        });
        return;
      }

      final userData = await _apiService.getMe(token);
      final role = userData['role'];
      if (role != 'ADMIN') {
        if (!mounted) return;
        setState(() {
          _userName = null;
        });
        return;
      }

      setState(() {
        _userName = userData['full_name'];
      });

      // Phase 1: Load essential data first (core metrics)
      await _loadPhase1EssentialData(token);

      // Phase 2: Load secondary data (team info, pending approvals)
      await _loadPhase2SecondaryData(token);

      // Phase 3: Load detailed analytics (on demand via refresh)
      _phase3Loaded = false;

      debugPrint('[ADMIN] Phase 1 & 2 data loaded progressively');
    } catch (e) {
      if (!mounted) return;
      debugPrint('[ADMIN] Error loading user data: $e');
    }
  }

  /// Phase 1: Load essential user information and core metrics immediately
  Future<void> _loadPhase1EssentialData(String token) async {
    if (!mounted) return;
    setState(() {
      _isLoadingOverview = true;
    });

    try {
      // Load organization overview
      final response = await _apiService.getMapWithAuth(
        '/admin/user-counts',
        token,
      );
      if (mounted && response != null) {
        setState(() {
          _employeesCount = response['employees'] ?? 0;
          _managersCount = response['managers'] ?? 0;
          _pendingCount = response['pending_users'] ?? 0;
        });
      }

      // Load workforce overview
      final workforceResponse = await _apiService.getMapWithAuth(
        '/admin/active-sessions',
        token,
      );
      if (mounted && workforceResponse != null) {
        setState(() {
          _activeSessionsCount = workforceResponse['active_sessions'] ?? 0;
          _activeBreaksCount = workforceResponse['active_breaks'] ?? 0;
        });
      }

      if (!mounted) return;
      setState(() {
        _isLoadingOverview = false;
      });

      debugPrint('[ADMIN] Phase 1 essential data loaded');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingOverview = false;
      });
    }
  }

  /// Phase 2: Load secondary data (team info, pending approvals)
  Future<void> _loadPhase2SecondaryData(String token) async {
    if (!mounted) return;
    setState(() {
      _isLoadingPending = true;
    });

    try {
      // Load pending approvals (limit to 3 for dashboard preview)
      final pendingUsers = await _apiService.getListWithAuth(
        '/admin/pending-users',
        token,
      );
      if (mounted) {
        setState(() {
          _pendingUsers = pendingUsers.take(3).toList();
        });
      }

      // Load team members and teams
      await Future.wait([
        _loadTeamMembers(token),
        _loadTeams(token),
      ]);

      if (!mounted) return;
      setState(() {
        _isLoadingPending = false;
      });

      debugPrint('[ADMIN] Phase 2 secondary data loaded');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPending = false;
      });
    }
  }

  Future<void> _loadTeamMembers(String token) async {
    try {
      final teamProvider = Provider.of<TeamProvider>(context, listen: false);
      if (teamProvider.hasTeam) {
        await teamProvider.loadTeamMembers(teamProvider.currentTeam!.id, token);
      }
    } catch (e) {
      // Ignore - not critical
    }
  }

  Future<void> _loadTeams(String token) async {
    try {
      await Provider.of<TeamProvider>(context, listen: false).loadMyTeam(token);
    } catch (e) {
      // Ignore - not critical
    }
  }

  /// Phase 3: Load detailed analytics (triggered on demand via refresh button)
  Future<void> _loadPhase3Analytics(String token) async {
    if (_phase3Loaded) return;
    if (!mounted) return;
    setState(() {
      _phase3Loaded = true;
    });

    try {
      // Load today's focus ratio
      final focusRatioResponse = await _apiService.getMapWithAuth(
        '/analytics/admin/today/focus-ratio',
        token,
      );
      if (mounted) {
        setState(() {
          _todayFocusRatio = {
            'activeFocus': focusRatioResponse?['activeFocus'] ?? 0.0,
            'idle': focusRatioResponse?['idle'] ?? 0.0,
            'nonActive': focusRatioResponse?['nonActive'] ?? 0.0,
          };
        });
      }

      // Load weekly focus/idle data
      final weeklyFocusResponse = await _apiService.getListWithAuth(
        '/analytics/admin/weekly-focus-idle',
        token,
      );
      if (mounted) {
        setState(() {
          _weeklyFocusIdle = weeklyFocusResponse ?? [];
        });
      }

      // Load focus rate
      final focusRateResponse = await _apiService.getMapWithAuth(
        '/analytics/admin/focus-rate',
        token,
      );
      if (mounted) {
        setState(() {
          _focusRate = (focusRateResponse?['focus_rate'] ?? 0.0).toDouble();
        });
      }

      // Load weekly work hours
      final weeklyHoursResponse = await _apiService.getListWithAuth(
        '/analytics/admin/weekly-work-hours',
        token,
      );
      if (mounted) {
        setState(() {
          _weeklyWorkHours = weeklyHoursResponse ?? [];
        });
      }

      debugPrint('[ADMIN] Phase 3 analytics data loaded');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase3Loaded = false;
      });
    }
  }

  Future<void> _loadRecentSystemActivity(
    String token, {
    bool refresh = false,
  }) async {
    if (refresh) {
      _auditLogsPage = 1;
      _auditLogs.clear();
      _hasMoreAuditLogs = true;
    }

    if (!_hasMoreAuditLogs) return;

    try {
      setState(() {
        _auditLogsLoading = true;
        if (_auditLogs.isEmpty && refresh) {
          _auditLogs.clear();
        }
      });

      final auditLogs = await _apiService.getAuditLogs(
        token,
        page: _auditLogsPage,
        limit: _auditLogsLimit,
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

  void _loadMoreAuditLogs() async {
    final token = await _apiService.getToken();
    if (token != null) {
      await _loadRecentSystemActivity(token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: isDesktop
                ? _buildDesktopLayout(context)
                : _buildMobileLayout(context),
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: GreetingSection(
                isGuest: false,
                userName: _userName != null ? 'Admin $_userName' : 'Admin',
              ),
            ),
          const SizedBox(height: 24),

          // Organization Overview
          _buildSectionHeader(
            context,
            'Organization Overview',
            Icons.account_tree,
          ),
          _buildOrganizationOverviewCards(context),
          const SizedBox(height: 24),

          // Workforce Overview
          _buildSectionHeader(context, 'Workforce Overview', Icons.people),
          _buildWorkforceOverviewCards(context),
          const SizedBox(height: 24),

          // Pending Approvals
          _buildSectionHeader(
            context,
            'Pending Approvals',
            Icons.pending_actions,
          ),
          _buildPendingApprovalsSection(context),
          const SizedBox(height: 24),

          // People Management & Teams/Organization Structure side by side
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      context,
                      'People Management',
                      Icons.groups,
                    ),
                    _buildPeopleManagementSection(context),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      context,
                      'Teams / Organization Structure',
                      Icons.account_tree,
                    ),
                    _buildTeamsOrganizationSection(context),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Organization Analytics
          _buildSectionHeader(
            context,
            'Organization Analytics',
            Icons.analytics,
          ),
          _buildOrganizationAnalyticsSection(context),
          const SizedBox(height: 24),

          // Recent System Activity
          _buildSectionHeader(
            context,
            'Recent System Activity',
            Icons.history,
          ),
          _buildRecentSystemActivitySection(
            context,
            auditLogs: _auditLogs,
            auditLogsPage: _auditLogsPage,
            hasMoreAuditLogs: _hasMoreAuditLogs,
            auditLogsLoading: _auditLogsLoading,
            auditLogsError: _auditLogsError,
            onLoadMore: _loadMoreAuditLogs,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          GreetingSection(
            isGuest: false,
            userName: _userName != null ? 'Admin $_userName' : 'Admin',
          ),
          const SizedBox(height: 24),

          // Organization Overview
          _buildSectionHeader(
            context,
            'Organization Overview',
            Icons.account_tree,
          ),
          _buildOrganizationOverviewCards(context),
          const SizedBox(height: 24),

          // Workforce Overview
          _buildSectionHeader(context, 'Workforce Overview', Icons.people),
          _buildWorkforceOverviewCards(context),
          const SizedBox(height: 24),

          // Pending Approvals
          _buildSectionHeader(
            context,
            'Pending Approvals',
            Icons.pending_actions,
          ),
          _buildPendingApprovalsSection(context),
          const SizedBox(height: 24),

          // People Management
          _buildSectionHeader(
            context,
            'People Management',
            Icons.groups,
          ),
          _buildPeopleManagementSection(context),
          const SizedBox(height: 24),

          // Teams / Organization Structure
          _buildSectionHeader(
            context,
            'Teams / Organization Structure',
            Icons.account_tree,
          ),
          _buildTeamsOrganizationSection(context),
          const SizedBox(height: 24),

          // Organization Analytics
          _buildSectionHeader(
            context,
            'Organization Analytics',
            Icons.analytics,
          ),
          _buildOrganizationAnalyticsSection(context),
          const SizedBox(height: 24),

          // Recent System Activity
          _buildSectionHeader(
            context,
            'Recent System Activity',
            Icons.history,
          ),
          _buildRecentSystemActivitySection(
            context,
            auditLogs: _auditLogs,
            auditLogsPage: _auditLogsPage,
            hasMoreAuditLogs: _hasMoreAuditLogs,
            auditLogsLoading: _auditLogsLoading,
            auditLogsError: _auditLogsError,
            onLoadMore: _loadMoreAuditLogs,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrganizationOverviewCards(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            context,
            'Employees',
            _employeesCount.toString(),
            Icons.people,
            colorScheme.primary,
            _isLoadingOverview,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            context,
            'Managers',
            _managersCount.toString(),
            Icons.person_pin,
            colorScheme.secondary,
            _isLoadingOverview,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            context,
            'Pending Approvals',
            _pendingCount.toString(),
            Icons.pending_actions,
            colorScheme.tertiary,
            _isLoadingOverview,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
    bool isLoading,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 24, color: color),
              const Spacer(),
              if (isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkforceOverviewCards(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            context,
            'Active Sessions',
            _activeSessionsCount.toString(),
            Icons.work,
            Colors.green,
            _isLoadingOverview,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            context,
            'Active Breaks',
            _activeBreaksCount.toString(),
            Icons.coffee,
            Colors.orange,
            _isLoadingOverview,
          ),
        ),
      ],
    );
  }

  Widget _buildPendingApprovalsSection(BuildContext context) {
    if (_isLoadingPending && _pendingUsers.isEmpty) {
      return _buildLoadingPlaceholder(context);
    }

    if (_pendingUsers.isEmpty) {
      return _buildEmptyState(
        context,
        'No pending approvals',
        Icons.check_circle_outline,
        'All requests have been processed',
      );
    }

    return Column(
      children: _pendingUsers.map((user) {
        final name = user['full_name'] ?? 'Unknown';
        final email = user['email'] ?? '';
        final role = user['role'] ?? 'EMPLOYEE';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('$email • $role'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () => _approveUser(user['id']),
                  tooltip: 'Approve',
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _rejectUser(user['id']),
                  tooltip: 'Reject',
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _approveUser(String userId) async {
    final token = await _apiService.getToken();
    if (token == null) return;

    try {
      await _apiService.postWithAuth(
        '/admin/users/$userId/approve',
        token,
        {},
      );
      if (mounted) {
        setState(() {
          _pendingUsers.removeWhere((u) => u['id'] == userId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User approved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to approve: $e')),
        );
      }
    }
  }

  Future<void> _rejectUser(String userId) async {
    final token = await _apiService.getToken();
    if (token == null) return;

    try {
      await _apiService.postWithAuth(
        '/admin/users/$userId/reject',
        token,
        {},
      );
      if (mounted) {
        setState(() {
          _pendingUsers.removeWhere((u) => u['id'] == userId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User rejected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reject: $e')),
        );
      }
    }
  }

  Widget _buildPeopleManagementSection(BuildContext context) {
    return Consumer<TeamProvider>(
      builder: (context, teamProvider, child) {
        if (!teamProvider.hasTeam) {
          return _buildEmptyState(
            context,
            'No team data available',
            Icons.groups_outlined,
            'Team members will appear here',
          );
        }

        final members = teamProvider.teamMembers;

        if (members.isEmpty) {
          return _buildEmptyState(
            context,
            'No team members',
            Icons.person_off_outlined,
            'Add members to your team',
          );
        }

        return Column(
          children: members.take(10).map((member) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    member.userName?[0]?.toUpperCase() ?? '?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  member.userName ?? 'Unknown',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '${member.userEmail ?? ''} • ${member.role ?? 'EMPLOYEE'}',
                ),
                trailing: member.isCurrent
                    ? Chip(
                        label: const Text('Active'),
                        backgroundColor: Colors.green.withValues(alpha: 0.1),
                        labelStyle: const TextStyle(color: Colors.green, fontSize: 12),
                      )
                    : Chip(
                        label: const Text('Inactive'),
                        backgroundColor: Colors.grey.withValues(alpha: 0.1),
                        labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildTeamsOrganizationSection(BuildContext context) {
    return Consumer<TeamProvider>(
      builder: (context, teamProvider, child) {
        if (!teamProvider.hasTeam) {
          return _buildEmptyState(
            context,
            'No teams found',
            Icons.account_tree_outlined,
            'Create a team to get started',
          );
        }

        final team = teamProvider.currentTeam!;

        return Column(
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                  child: Icon(
                    Icons.groups,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                title: Text(
                  team.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '${team.memberCount} members • ${team.description ?? 'No description'}',
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onTap: () {
                  // Navigate to team details
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOrganizationAnalyticsSection(BuildContext context) {
    if (!_phase3Loaded) {
      return Column(
        children: [
          _buildLoadingPlaceholder(context),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final token = await _apiService.getToken();
              if (token != null) {
                await _loadPhase3Analytics(token);
              }
            },
            icon: const Icon(Icons.analytics),
            label: const Text('Load Analytics'),
          ),
        ],
      );
    }

    return Column(
      children: [
        // Today's Focus Ratio
        Row(
          children: [
            Expanded(
              child: _buildFocusRatioCard(
                context,
                'Active Focus',
                (_todayFocusRatio['activeFocus'] ?? 0.0) * 100,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildFocusRatioCard(
                context,
                'Idle',
                (_todayFocusRatio['idle'] ?? 0.0) * 100,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildFocusRatioCard(
                context,
                'Non-Active',
                (_todayFocusRatio['nonActive'] ?? 0.0) * 100,
                Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Focus Rate
        _buildFocusRateCard(context),
        const SizedBox(height: 24),

        // Weekly Focus/Idle Chart
        if (_weeklyFocusIdle.isNotEmpty)
          SizedBox(
            height: 300,
            child: FocusIdleLineChart(
              // data: _weeklyFocusIdle,
            ),
          ),
        const SizedBox(height: 24),

        // Weekly Work Hours
        if (_weeklyWorkHours.isNotEmpty)
          _buildWeeklyWorkHoursChart(context),
      ],
    );
  }

  Widget _buildFocusRatioCard(
    BuildContext context,
    String label,
    double percentage,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: percentage / 100,
                  strokeWidth: 8,
                  backgroundColor: color.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFocusRateCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall Focus Rate',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Percentage of time in active focus',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Text(
            '${(_focusRate * 100).toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyWorkHoursChart(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly Work Hours',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: CustomPaint(
              painter: _WeeklyWorkHoursPainter(
                data: _weeklyWorkHours,
                color: Theme.of(context).colorScheme.primary,
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyWorkHoursPainter extends CustomPainter {
  final List<dynamic> data;
  final Color color;

  _WeeklyWorkHoursPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final backgroundPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    const barWidth = 30.0;
    const spacing = 15.0;
    final totalWidth = (barWidth + spacing) * data.length - spacing;
    final startX = (size.width - totalWidth) / 2;

    double maxValue = 1;
    for (final item in data) {
      final value = (item['hours'] ?? 0).toDouble();
      if (value > maxValue) maxValue = value;
    }

    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      final value = (item['hours'] ?? 0).toDouble();
      final height = (value / maxValue) * (size.height - 30);
      final x = startX + i * (barWidth + spacing);
      final y = size.height - 20 - height;

      // Background
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - 20 - (size.height - 30), barWidth, size.height - 30),
        backgroundPaint,
      );

      // Bar
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, height),
          const Radius.circular(4),
        ),
        paint,
      );

      // Label
      final dayText = item['day'] ?? '';
      final textPainter = TextPainter(
        text: TextSpan(
          text: dayText,
          style: TextStyle(
            color: color.withValues(alpha: 0.6),
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x + barWidth / 2 - textPainter.width / 2, size.height - 15),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

  Widget _buildRecentSystemActivitySection(BuildContext context,
      {required List<dynamic> auditLogs,
      required int auditLogsPage,
      required bool hasMoreAuditLogs,
      required bool auditLogsLoading,
      required String? auditLogsError,
      required VoidCallback onLoadMore}) {
    if (auditLogsLoading && auditLogs.isEmpty) {
      return _buildLoadingPlaceholder(context);
    }

    if (auditLogsError != null) {
      return _buildErrorState(context, auditLogsError!);
    }

    if (auditLogs.isEmpty) {
      return _buildEmptyState(
        context,
        'No recent activity',
        Icons.history_outlined,
        'System activity will appear here',
      );
    }

    return Column(
      children: [
        ...auditLogs.map((log) {
          final action = log['action'] ?? 'Unknown';
          final user = log['user'] ?? 'System';
          final timestamp = log['timestamp'] ?? '';
          final details = log['details'] ?? '';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                child: Icon(
                  _getActionIcon(action),
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                  size: 20,
                ),
              ),
              title: Text(
                action,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$user • $timestamp'),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              trailing: auditLogsLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
          );
        }),
        if (hasMoreAuditLogs)
          Center(
            child: TextButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(Icons.expand_more),
              label: const Text('Load More'),
            ),
          ),
      ],
    );
  }

  IconData _getActionIcon(String action) {
  switch (action.toLowerCase()) {
    case 'login':
      return Icons.login;
    case 'logout':
      return Icons.logout;
    case 'create':
      return Icons.add;
    case 'update':
      return Icons.edit;
    case 'delete':
      return Icons.delete;
    case 'approve':
      return Icons.check_circle;
    case 'reject':
      return Icons.cancel;
    default:
      return Icons.info;
  }
}

Widget _buildLoadingPlaceholder(BuildContext context) {
  return Container(
    height: 100,
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Center(
      child: CircularProgressIndicator(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

Widget _buildEmptyState(
  BuildContext context,
  String title,
  IconData icon,
  String subtitle,
) {
  return Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
      ),
    ),
    child: Column(
      children: [
        Icon(
          icon,
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

Widget _buildErrorState(BuildContext context, String error) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.red.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.red),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Error: $error',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    ),
  );
}