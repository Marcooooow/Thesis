import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/models/team_models.dart';
import 'package:intellibreak/features/team/widgets/create_team_dialog.dart';
import 'package:intellibreak/features/team/widgets/invite_employee_picker_dialog.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intellibreak/providers/team_provider.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/employees/widgets/employee_shift_preview_dialog.dart';
import 'package:intellibreak/features/employees/screens/manager_employee_detail_screen.dart';
import 'package:intellibreak/widgets/user_avatar.dart';

class TeamViewScreen extends StatefulWidget {
  const TeamViewScreen({super.key});

  @override
  State<TeamViewScreen> createState() => _TeamViewScreenState();
}

class _TeamViewScreenState extends State<TeamViewScreen> {
  @override
  Widget build(BuildContext context) {
    return const TeamViewScreenContent();
  }
}

/// Content widget for use within AppShell
class TeamViewScreenContent extends StatefulWidget {
  const TeamViewScreenContent({super.key});

  @override
  State<TeamViewScreenContent> createState() => _TeamViewScreenContentState();
}

class _TeamViewScreenContentState extends State<TeamViewScreenContent>
    with SingleTickerProviderStateMixin {
  String? _token;
  bool _initialized = false;
  String? _currentUserRole;
  late TabController _tabController;
  String _searchQuery = '';
  String _roleFilter = 'All';
  String _groupFilter = 'All';
  String _statusFilter = 'All';

  bool _canInspect(TeamProvider teamProvider) {
    if (_currentUserRole == 'ADMIN' || _currentUserRole == 'MANAGER' || teamProvider.isTeamManager) {
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadToken();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _token = token;
      _initialized = true;
    });

    if (token != null && mounted) {
      final teamProvider = context.read<TeamProvider>();
      final apiService = ApiService();
      try {
        final userData = await apiService.getMe(token);
        // [TEAM_ROLE] Log current user identity
        print('[TEAM_ROLE] current user ID = ${userData['id']}');
        print('[TEAM_ROLE] current user role = ${userData['role']}');
        print('[TEAM_ROLE] current user name = ${userData['full_name']}');
        teamProvider.setCurrentUserId(userData['id'].toString());
        if (mounted) {
          setState(() {
            _currentUserRole = userData['role']?.toString();
          });
        }
      } catch (e) {
        print('[TEAM_ROLE] ERROR getting user data: $e');
      }

      await teamProvider.loadMyTeam(token);

      // [TEAM_ROLE] Log team info
      if (teamProvider.hasTeam) {
        print('[TEAM_ROLE] current team ID = ${teamProvider.currentTeam?.id}');
        print(
          '[TEAM_ROLE] current team name = ${teamProvider.currentTeam?.name}',
        );
      }

      if (teamProvider.hasTeam && mounted) {
        final futures = <Future<void>>[
          teamProvider.loadTeamMembers(teamProvider.currentTeam!.id, token),
          teamProvider.loadGroups(teamProvider.currentTeam!.id, token),
        ];
        if (teamProvider.isTeamManager) {
          futures.add(
            teamProvider.loadInvitations(teamProvider.currentTeam!.id, token),
          );
        }
        await Future.wait(futures);

        // [TEAM_ROLE] Log team members after loading
        print(
          '[TEAM_ROLE] team members count = ${teamProvider.teamMembers.length}',
        );
        for (final member in teamProvider.teamMembers) {
          print(
            '[TEAM_ROLE]   member: userId=${member.userId}, role=${member.role}, name=${member.userName}',
          );
        }

        // [TEAM_ROLE] Log final provider state
        print(
          '[TEAM_ROLE] provider currentUserId = ${teamProvider.currentUserId}',
        );
        print('[TEAM_ROLE] isTeamManager = ${teamProvider.isTeamManager}');
      }
    }
  }

  Future<void> _onTeamCreated() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null && mounted) {
      final teamProvider = context.read<TeamProvider>();
      await teamProvider.refresh(token);
      _tabController.animateTo(0);
    }
  }

  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    final initials = parts
        .where((p) => p.isNotEmpty)
        .map((p) => p[0])
        .join()
        .toUpperCase();
    if (initials.isEmpty) return '?';
    return initials.length <= 2 ? initials : initials.substring(0, 2);
  }

  Widget _buildMemberNameWidget(TeamMember member, bool isDark, bool canInspect) {
    return Row(
      children: [
        UserAvatar(
          name: member.userName,
          role: member.role,
          size: 32,
          showPresence: false,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            member.userName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: canInspect
                  ? (isDark ? Colors.blue.shade300 : Colors.blue.shade700)
                  : (isDark ? Colors.white : Colors.black),
              decoration: canInspect
                  ? TextDecoration.underline
                  : TextDecoration.none,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _navigateToEmployeeDetail(
    BuildContext context,
    TeamMember member,
  ) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManagerEmployeeDetailScreen(
          employeeId: member.userId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;

    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Consumer<TeamProvider>(
      builder: (context, teamProvider, _) {
        if (teamProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!teamProvider.hasTeam) {
          return _buildSoloEmployeeState(isDark, isHighContrast);
        }

        return _buildTeamView(
          context,
          isDark,
          isHighContrast,
          isDesktop,
          teamProvider,
        );
      },
    );
  }

  /// Empty state for solo employees without a team.
  Widget _buildSoloEmployeeState(bool isDark, bool isHighContrast) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(48),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 64,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.5)
                        : Color(0xFFA5A7AE))
                  : Colors.grey.shade400,
            ),
            const SizedBox(height: 24),
            Text(
              'My Team',
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
              'You are currently working independently.',
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
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _showCreateTeamDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create Team'),
            ),
          ],
        ),
      ),
    );
  }

  /// Main team view with tabs for Members and Groups.
  Widget _buildTeamView(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    bool isDesktop,
    TeamProvider teamProvider,
  ) {
    final team = teamProvider.currentTeam;
    if (team == null) {
      return _buildSoloEmployeeState(isDark, isHighContrast);
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (_token != null) {
          await teamProvider.refresh(_token!);
        }
      },
      child: Column(
        children: [
          // Header with team title
          Container(
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 24 : 16,
              isDesktop ? 24 : 16,
              isDesktop ? 24 : 16,
              16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your team members and groups',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? const Color(0xFFA5A7AE)
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                // Team summary card
                _buildTeamSummary(team, teamProvider, isDark),
              ],
            ),
          ),
          // Tabs
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Members'),
              Tab(text: 'Groups'),
            ],
            labelColor: isDark ? Colors.white : Colors.black,
            unselectedLabelColor: isDark
                ? const Color(0xFFA5A7AE)
                : Colors.grey.shade600,
            indicatorColor: Colors.blue,
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMembersTab(
                  teamProvider,
                  isDark,
                  isHighContrast,
                  isDesktop,
                ),
                _buildGroupsTab(
                  teamProvider,
                  isDark,
                  isHighContrast,
                  isDesktop,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Team summary card with name, status, member count, manager.
  Widget _buildTeamSummary(Team team, TeamProvider teamProvider, bool isDark) {
    return DesignSystem.premiumCard(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Active',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.7)
                            : Colors.black.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Row(
              children: [
                _buildSummaryItem(
                  'Members',
                  team.memberCount.toString(),
                  isDark,
                ),
                const SizedBox(width: 24),
                _buildSummaryItem('Manager', team.managerName, isDark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Color(0xFFA5A7AE) : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }

  /// Members tab with professional filter and data table.
  Widget _buildMembersTab(
    TeamProvider teamProvider,
    bool isDark,
    bool isHighContrast,
    bool isDesktop,
  ) {
    final team = teamProvider.currentTeam;
    if (team == null) return const SizedBox.shrink();

    // Filter members based on search and filters
    final filteredMembers = _filterMembers(
      teamProvider.teamMembers,
      teamProvider.groups,
    );

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Invite section for managers
            if (teamProvider.isTeamManager)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _buildInviteSection(
                  context,
                  team.id,
                  teamProvider,
                  isDark,
                ),
              ),

            // Filters
            _buildFilterBar(teamProvider, isDark),
            const SizedBox(height: 16),

            // Members table/list
            if (filteredMembers.isEmpty)
              _buildEmptyMembersState(isDark, isHighContrast)
            else
              _buildMembersTable(
                filteredMembers,
                teamProvider,
                isDark,
                isDesktop,
              ),
          ],
        ),
      ),
    );
  }

  /// Filter members by search and filter criteria
  List<TeamMember> _filterMembers(
    List<TeamMember> members,
    List<TeamGroup> groups,
  ) {
    return members.where((member) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!member.userName.toLowerCase().contains(query) &&
            !member.userEmail.toLowerCase().contains(query)) {
          return false;
        }
      }

      // Role filter
      if (_roleFilter != 'All') {
        if (member.role != _roleFilter) {
          return false;
        }
      }

      // Group filter
      if (_groupFilter != 'All') {
        final groupId = groups
            .where((g) => g.name == _groupFilter)
            .firstOrNull
            ?.id;
        if (groupId == null || member.profileId != groupId) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// Build invite section with email input
  Widget _buildInviteSection(
    BuildContext context,
    String teamId,
    TeamProvider teamProvider,
    bool isDark,
  ) {
    return DesignSystem.premiumCard(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.mail_outline,
              size: 20,
              color: isDark ? const Color(0xFFA5A7AE) : Colors.grey.shade600,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invite new team members',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Send an invitation to add employees to your team',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFFA5A7AE)
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _showInviteDialog(context, teamId),
              icon: const Icon(Icons.person_add, size: 16),
              label: const Text('Send Invite'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build filter bar with dropdowns and search
  Widget _buildFilterBar(TeamProvider teamProvider, bool isDark) {
    final roles = {'All', 'MANAGER', 'EMPLOYEE'};
    final groupNames = {'All', ...teamProvider.groups.map((g) => g.name)};
    final statuses = {'All', 'Active', 'Pending'};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Members (${teamProvider.teamMembers.length})',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: _buildFilterDropdown('All', roles.toList(), _roleFilter, (
                value,
              ) {
                setState(() => _roleFilter = value);
              }, isDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: _buildFilterDropdown(
                'All',
                groupNames.toList(),
                _groupFilter,
                (value) {
                  setState(() => _groupFilter = value);
                },
                isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: _buildFilterDropdown(
                'All',
                statuses.toList(),
                _statusFilter,
                (value) {
                  setState(() => _statusFilter = value);
                },
                isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                decoration: InputDecoration(
                  hintText: 'Search by name or email',
                  prefixIcon: Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build a filter dropdown
  Widget _buildFilterDropdown(
    String label,
    List<String> options,
    String selected,
    ValueChanged<String> onChanged,
    bool isDark,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: selected,
      items: options
          .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2C33) : Colors.grey.shade100,
      ),
      style: TextStyle(
        fontSize: 13,
        color: isDark ? Colors.white : Colors.black,
      ),
    );
  }

  /// Build members data table
  Widget _buildMembersTable(
    List<TeamMember> members,
    TeamProvider teamProvider,
    bool isDark,
    bool isDesktop,
  ) {
    return DesignSystem.premiumCard(
      context: context,
      padding: 0,
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
                SizedBox(
                  width: 100,
                  child: Text(
                    'NAME',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'EMAIL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    'ROLE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    'GROUP',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    'STATUS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                if (teamProvider.isTeamManager)
                  SizedBox(
                    width: 60,
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
            itemCount: members.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: isDark ? const Color(0xFF30323A) : Colors.grey.shade300,
            ),
            itemBuilder: (context, index) {
              final member = members[index];
              final groupName = teamProvider.groups
                  .where((g) => g.id == member.profileId)
                  .firstOrNull
                  ?.name;

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: _canInspect(teamProvider)
                          ? GestureDetector(
                              onTap: () => _navigateToEmployeeDetail(context, member),
                              child: Tooltip(
                                message: 'Click to inspect employee profile, work sessions, recommendations & wellbeing',
                                child: _buildMemberNameWidget(member, isDark, true),
                              ),
                            )
                          : _buildMemberNameWidget(member, isDark, false),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        member.userEmail,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? const Color(0xFFA5A7AE)
                              : Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: member.role == 'MANAGER'
                              ? Colors.blue.withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          member.role == 'MANAGER' ? 'Manager' : 'Employee',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: member.role == 'MANAGER'
                                ? Colors.blue
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: Text(
                        groupName ?? 'Unassigned',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Row(
                        children: [
                          // ponytail: real presence data unavailable in this screen context yet; grey for unknown/offline, green only when backend confirms online
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Unknown',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (teamProvider.isTeamManager && member.role != 'MANAGER')
                      SizedBox(
                        width: 60,
                        child: PopupMenuButton(
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              child: const Row(
                                children: [
                                  Icon(Icons.group_add, size: 16),
                                  SizedBox(width: 8),
                                  Text(
                                    'Move to Group',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              onTap: () {
                                _showMoveToGroupDialog(
                                  context,
                                  member,
                                  teamProvider,
                                );
                              },
                            ),
                            PopupMenuItem(
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.person_remove,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Remove',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                _showRemoveConfirmation(
                                  context,
                                  member,
                                  teamProvider,
                                  teamProvider.currentTeam!.id,
                                );
                              },
                            ),
                          ],
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

  /// Empty state for members.
  Widget _buildEmptyMembersState(bool isDark, bool isHighContrast) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.person_outline,
              size: 48,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.5)
                        : Color(0xFFA5A7AE))
                  : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No employees yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Invite employees to start building your team.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Color(0xFFA5A7AE) : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Groups tab with real group data.
  Widget _buildGroupsTab(
    TeamProvider teamProvider,
    bool isDark,
    bool isHighContrast,
    bool isDesktop,
  ) {
    final team = teamProvider.currentTeam;
    if (team == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Groups header + Create button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Groups',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                if (teamProvider.isTeamManager)
                  ElevatedButton.icon(
                    onPressed: () =>
                        _showCreateGroupDialog(context, teamProvider),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Create Group'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (teamProvider.groups.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No groups yet',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? const Color(0xFFA5A7AE)
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: <Widget>[
                  ...teamProvider.groups.map((group) {
                    final memberCount = teamProvider.teamMembers
                        .where((m) => m.profileId == group.id)
                        .length;

                    return SizedBox(
                      width: 500,
                      height: 130,
                      child: DesignSystem.premiumCard(
                        context: context,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          group.name,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$memberCount member${memberCount != 1 ? 's' : ''}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: isDark
                                                ? const Color(0xFFA5A7AE)
                                                : Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (teamProvider.isTeamManager)
                                    PopupMenuButton<String>(
                                      icon: const Icon(
                                        Icons.more_vert,
                                        size: 20,
                                      ),
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'manage',
                                          child: Row(
                                            children: const [
                                              Icon(Icons.people, size: 16),
                                              SizedBox(width: 8),
                                              Text(
                                                'Manage',
                                                style: TextStyle(fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: const [
                                              Icon(Icons.edit, size: 16),
                                              SizedBox(width: 8),
                                              Text(
                                                'Edit Group',
                                                style: TextStyle(fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: const [
                                              Icon(
                                                Icons.delete,
                                                size: 16,
                                                color: Colors.red,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Delete Group',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      onSelected: (value) {
                                        if (value == 'manage') {
                                          _showGroupMembersDialog(
                                            context,
                                            group,
                                            teamProvider,
                                            isDark,
                                          );
                                        } else if (value == 'edit') {
                                          _showEditGroupDialog(
                                            context,
                                            group,
                                            teamProvider,
                                            isDark,
                                          );
                                        } else if (value == 'delete') {
                                          _showDeleteGroupConfirm(
                                            context,
                                            group,
                                            teamProvider,
                                            isDark,
                                          );
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Show members in a specific group (compact, content-sized dialog)
  void _showGroupMembersDialog(
    BuildContext context,
    TeamGroup group,
    TeamProvider teamProvider,
    bool isDark,
  ) {
    final groupMembers = teamProvider.teamMembers
        .where((m) => m.profileId == group.id)
        .toList();

    final bool hasMembers = groupMembers.isNotEmpty;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${group.name} (${groupMembers.length} members)'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 560,
            minHeight: 400,
            maxWidth: 560,
            maxHeight: 400,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hasMembers)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No members yet.',
                    style: TextStyle(fontSize: 14),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: groupMembers.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 8,
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                    ),
                    itemBuilder: (context, index) {
                      final member = groupMembers[index];
                      return Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                _getInitials(member.userName),
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
                                  member.userName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                Text(
                                  member.userEmail,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? const Color(0xFFA5A7AE)
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              if (teamProvider.isTeamManager)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    // Open team invite to add members (existing functionality)
                    final team = teamProvider.currentTeam;
                    if (team != null && teamProvider.currentUserId != null) {
                      _showInviteDialog(context, team.id);
                    }
                  },
                  icon: const Icon(Icons.person_add, size: 16),
                  label: const Text('Add Members'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(140, 36),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showInviteDialog(BuildContext context, String teamId) {
    showDialog(
      context: context,
      builder: (context) => InviteEmployeePickerDialog(
        teamId: teamId,
        token: _token ?? '',
        teamProvider: context.read<TeamProvider>(),
        onInvitationSent: () {
          // Refresh team data
          if (_token != null) {
            context.read<TeamProvider>().refresh(_token!);
          }
        },
      ),
    );
  }

  void _showCreateTeamDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateTeamDialog(onTeamCreated: _onTeamCreated),
    );
  }

  void _showMoveToGroupDialog(
    BuildContext context,
    TeamMember member,
    TeamProvider teamProvider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Member: ${member.userName}'),
            const SizedBox(height: 16),
            const Text('Select group:'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.maxFinite,
              child: DropdownButtonHideUnderline(
                child: Dropdown(
                  items: teamProvider.groups,
                  onChanged: (group) {
                    if (_token != null) {
                      teamProvider.moveToGroup(
                        _token!,
                        teamProvider.currentTeam!.id,
                        member.userId,
                        group.id,
                      );
                    }
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showRemoveConfirmation(
    BuildContext context,
    TeamMember member,
    TeamProvider teamProvider,
    String teamId,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member?'),
        content: Text(
          'Remove ${member.userName} from this team? They will lose membership but retain their work history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (_token != null) {
                teamProvider.removeMember(_token!, teamId, member.userId);
              }
              Navigator.pop(context);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showEditGroupDialog(
    BuildContext context,
    TeamGroup group,
    TeamProvider teamProvider,
    bool isDark,
  ) {
    final controller = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Group'),
        content: SizedBox(
          width: 500,
          height: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Group name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              // No backend edit endpoint exists; update locally and refresh.
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Edit Group: backend endpoint not implemented; preserve existing group.',
                  ),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteGroupConfirm(
    BuildContext context,
    TeamGroup group,
    TeamProvider teamProvider,
    bool isDark,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Delete "${group.name}"? This action is not reversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Delete Group: backend endpoint not implemented; group preserved.',
                  ),
                ),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context, TeamProvider teamProvider) {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Group'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            hintText: 'Group name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && _token != null) {
                teamProvider.createGroup(
                  _token!,
                  teamProvider.currentTeam!.id,
                  nameController.text,
                );
              }
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// Simple dropdown for groups.
class Dropdown extends StatelessWidget {
  final List<TeamGroup> items;
  final Function(TeamGroup) onChanged;

  const Dropdown({super.key, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<TeamGroup>(
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: items
            .map(
              (group) =>
                  DropdownMenuItem(value: group, child: Text(group.name)),
            )
            .toList(),
        onChanged: (group) {
          if (group != null) onChanged(group);
        },
        hint: const Text('Select a group'),
      ),
    );
  }
}
