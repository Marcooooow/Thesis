import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TeamDetailsScreen extends StatefulWidget {
  final String teamId;
  final int initialTab;

  const TeamDetailsScreen({
    super.key,
    required this.teamId,
    this.initialTab = 0,
  });

  @override
  State<TeamDetailsScreen> createState() => _TeamDetailsScreenState();
}

class _TeamDetailsScreenState extends State<TeamDetailsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _teamDetail;
  List<dynamic> _teamMembers = [];

  @override
  void initState() {
    super.initState();
    _loadTeamData();
  }

  Future<void> _loadTeamData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    if (token != null) {
      try {
        // Fetch team detail
        final teamDetail = await _apiService.getMapWithAuth(
          '/teams/${widget.teamId}',
          token,
        );
        if (teamDetail != null && mounted) {
          setState(() {
            _teamDetail = teamDetail;
          });
        }

        // Fetch team members
        final members = await _apiService.getListWithAuth(
          '/teams/${widget.teamId}/members',
          token,
        );
        if (members != null && mounted) {
          setState(() {
            _teamMembers = members;
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
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
        _errorMessage = 'No authentication token found';
      });
    }
  }

  Future<void> _refreshData() async {
    await _loadTeamData();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;

    return Scaffold(
      appBar: AppBar(
        title: Text(_teamDetail?['name'] ?? 'Team Details'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorView(isDark, isHighContrast)
              : _buildTeamDetailsView(context, isDark, isHighContrast),
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
              'Error Loading Team Details',
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
                          : Color(0xFF9AA3AF))
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

  Widget _buildTeamDetailsView(
      BuildContext context,
      bool isDark,
      bool isHighContrast) {
    return DefaultTabController(
      length: 4,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              title: Text(_teamDetail?['name'] ?? 'Team Details'),
              pinned: true,
              forceElevated: innerBoxIsScrolled,
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Overview'),
                  Tab(text: 'Members'),
                  Tab(text: 'Activity'),
                  Tab(text: 'Analytics'),
                ],
              ),
            ),
          ];
        },
        body: TabBarView(
          children: [
            _buildOverviewTab(context, isDark, isHighContrast),
            _buildMembersTab(context, isDark, isHighContrast),
            _buildActivityTab(context, isDark, isHighContrast),
            _buildAnalyticsTab(context, isDark, isHighContrast),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab(
      BuildContext context,
      bool isDark,
      bool isHighContrast) {
    if (_teamDetail == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow(
            context,
            'Team Name',
            _teamDetail!['name'] ?? 'N/A',
            isDark,
            isHighContrast,
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            context,
            'Description',
            _teamDetail!['description'] ?? 'No description',
            isDark,
            isHighContrast,
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            context,
            'Manager',
            _teamDetail!['manager_name'] ?? 'No manager',
            isDark,
            isHighContrast,
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            context,
            'Status',
            (_teamDetail!['is_active'] ?? false) ? 'Active' : 'Inactive',
            isDark,
            isHighContrast,
            valueColor: (_teamDetail!['is_active'] ?? false)
                ? Colors.green
                : Colors.red,
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            context,
            'Created At',
            _teamDetail!['created_at'] ?? 'N/A',
            isDark,
            isHighContrast,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
      BuildContext context,
      String label,
      String value,
      bool isDark,
      bool isHighContrast, {
      Color? valueColor,
    }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? (isHighContrast ? Colors.white : Colors.white)
                  : Colors.black,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              color: valueColor ??
                  (isDark
                      ? (isHighContrast ? Colors.white : Colors.white)
                      : Colors.black),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMembersTab(
      BuildContext context,
      bool isDark,
      bool isHighContrast) {
    if (_teamMembers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.5)
                        : Color(0xFF9AA3AF))
                  : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No members found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add members to this team',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Color(0xFF9AA3AF) : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemCount: _teamMembers.length,
      itemBuilder: (context, index) {
        final member = _teamMembers[index];
        return ListTile(
          leading: const Icon(Icons.person),
          title: Text(
            member['full_name'] ?? 'N/A',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          subtitle: Text(
            member['job_role'] ?? 'No role',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                  : Colors.grey.shade600,
            ),
          ),
          trailing: Text(
            member['status'] ?? 'Unknown',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: (member['status'] ?? '').toLowerCase() == 'active'
                  ? Colors.green
                  : Colors.red,
            ),
          ),
        );
      },
    );
  }

  Widget _buildActivityTab(
      BuildContext context,
      bool isDark,
      bool isHighContrast) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time,
            size: 48,
            color: isDark
                ? (isHighContrast
                      ? Colors.white.withValues(alpha: 0.5)
                      : Color(0xFF9AA3AF))
                : Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Activity Feed',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Activity tracking for team interactions will be available here.',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Color(0xFF9AA3AF) : Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab(
      BuildContext context,
      bool isDark,
      bool isHighContrast) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.analytics,
            size: 48,
            color: isDark
                ? (isHighContrast
                      ? Colors.white.withValues(alpha: 0.5)
                      : Color(0xFF9AA3AF))
                : Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Team Analytics',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Analytics data such as work patterns and break compliance will be displayed here.',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Color(0xFF9AA3AF) : Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}