import 'package:flutter/material.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmployeeDetailsScreen extends StatefulWidget {
  final String employeeId;
  final VoidCallback? onBack;

  const EmployeeDetailsScreen({
    super.key,
    required this.employeeId,
    this.onBack,
  });

  @override
  State<EmployeeDetailsScreen> createState() => _EmployeeDetailsScreenState();
}

class _EmployeeDetailsScreenState extends State<EmployeeDetailsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _employeeDetail;
  List<dynamic> _workSessions = [];
  List<dynamic> _recommendations = [];
  List<dynamic> _wellbeing = [];
  bool _recLoading = false;
  bool _wbLoading = false;
  String? _recError;
  String? _wbError;

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
    _loadRecommendations();
    _loadWellbeing();
  }

  Future<void> _loadEmployeeData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    if (token != null) {
      try {
        // Fetch employee detail
        final employeeDetail = await _apiService.getMapWithAuth(
          '/employees/${widget.employeeId}',
          token,
        );
        if (employeeDetail != null && mounted) {
          setState(() {
            _employeeDetail = employeeDetail;
          });
        }

        // Fetch work sessions if API exists
        try {
          final workSessions = await _apiService.getListWithAuth(
            '/employees/${widget.employeeId}/work-sessions',
            token,
          );
          if (mounted) {
            setState(() {
              _workSessions = workSessions;
            });
          }
        } catch (e) {
          // Work sessions API might not exist yet - that's OK for foundation
          if (mounted) {
            setState(() {
              _workSessions = []; // Empty list for placeholder
            });
          }
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

  Future<void> _loadRecommendations() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;
    setState(() => _recLoading = true);
    try {
      final recs = await _apiService.getListWithAuth(
        '/admin/users/${widget.employeeId}/recommendations',
        token,
      );
      if (mounted) setState(() => _recommendations = recs);
    } catch (e) {
      if (mounted) setState(() => _recError = e.toString());
    } finally {
      if (mounted) setState(() => _recLoading = false);
    }
  }

  Future<void> _loadWellbeing() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;
    setState(() => _wbLoading = true);
    try {
      final wb = await _apiService.getListWithAuth(
        '/admin/users/${widget.employeeId}/wellbeing',
        token,
      );
      if (mounted) setState(() => _wellbeing = wb);
    } catch (e) {
      if (mounted) setState(() => _wbError = e.toString());
    } finally {
      if (mounted) setState(() => _wbLoading = false);
    }
  }

  Future<void> _refreshData() async {
    await _loadEmployeeData();
    await _loadRecommendations();
    await _loadWellbeing();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;

    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _errorMessage != null
            ? _buildErrorView(isDark, isHighContrast)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.onBack != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: ElevatedButton.icon(
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: const Text('Back to Employee List'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF2A2D3A) : Colors.grey.shade200,
                          foregroundColor: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  Expanded(
                    child: _buildEmployeeDetailsView(context, isDark, isHighContrast),
                  ),
                ],
              );

    if (widget.onBack != null) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_employeeDetail?['full_name'] ?? 'Employee Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to Accounts',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: content,
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
              'Error Loading Employee Details',
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

  String _getInitials(String? name) {
    if (name == null || name.trim().isEmpty) return 'U';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Widget _buildEmployeeDetailsView(
      BuildContext context,
      bool isDark,
      bool isHighContrast) {
    final String fullName = _employeeDetail?['full_name'] ?? 'Employee';
    final String email = _employeeDetail?['email'] ?? '';
    final String role = _employeeDetail?['role'] ?? 'EMPLOYEE';
    final String status = _employeeDetail?['approval_status'] ?? 'APPROVED';
    final String initials = _getInitials(fullName);
    final Color statusColor = _getStatusColor(status, isDark, isHighContrast);

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          // Profile Header Card with Avatar Initials & Semantic Status Badge
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF182029) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF2D3643) : Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.blue.shade900 : Colors.blue.shade100,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.blue.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? const Color(0xFF9AA3AF) : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Role: $role',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF9AA3AF) : Colors.grey.shade600,
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
          // Tab Bar
          Container(
            color: isDark ? const Color(0xFF182029) : Colors.grey.shade100,
            child: TabBar(
              isScrollable: true,
              labelColor: isDark ? Colors.white : Colors.blue.shade800,
              unselectedLabelColor: isDark ? const Color(0xFF9AA3AF) : Colors.grey.shade600,
              indicatorColor: Colors.blue,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Work Sessions'),
                Tab(text: 'Recommendations'),
                Tab(text: 'Wellbeing'),
              ],
            ),
          ),
          // Tab Bar View
          Expanded(
            child: TabBarView(
              children: [
                _buildOverviewTab(context, isDark, isHighContrast),
                _buildWorkSessionsTab(context, isDark, isHighContrast),
                _buildRecommendationsTab(context, isDark, isHighContrast),
                _buildWellbeingTab(context, isDark, isHighContrast),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(
      BuildContext context,
      bool isDark,
      bool isHighContrast) {
    if (_employeeDetail == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final bool isWide = MediaQuery.of(context).size.width >= 800;

    final basicInfoCard = _buildInfoCard(
      context,
      'Basic Information',
      Icons.person_outline,
      isDark,
      isHighContrast,
      [
        _buildDetailRow(context, 'Full Name', _employeeDetail!['full_name'] ?? 'N/A', isDark, isHighContrast),
        _buildDetailRow(context, 'Email', _employeeDetail!['email'] ?? 'N/A', isDark, isHighContrast),
        _buildDetailRow(context, 'Role', _employeeDetail!['role'] ?? 'N/A', isDark, isHighContrast),
        _buildDetailRow(context, 'Hire Date', _employeeDetail!['hire_date'] ?? 'N/A', isDark, isHighContrast),
      ],
    );

    final statusCard = _buildInfoCard(
      context,
      'Account Status',
      Icons.verified_user_outlined,
      isDark,
      isHighContrast,
      [
        _buildDetailRow(
          context,
          'Status',
          _employeeDetail!['approval_status'] ?? 'N/A',
          isDark,
          isHighContrast,
          valueColor: _getStatusColor(_employeeDetail!['approval_status'] ?? '', isDark, isHighContrast),
        ),
        _buildDetailRow(
          context,
          'Active',
          (_employeeDetail!['is_active'] ?? true) ? 'Yes' : 'No',
          isDark,
          isHighContrast,
        ),
      ],
    );

    final orgCard = _buildInfoCard(
      context,
      'Organization Information',
      Icons.business_outlined,
      isDark,
      isHighContrast,
      [
        _buildDetailRow(context, 'Organization', _employeeDetail!['organization_name'] ?? 'N/A', isDark, isHighContrast),
        _buildDetailRow(context, 'Department', _employeeDetail!['department'] ?? 'N/A', isDark, isHighContrast),
        _buildDetailRow(context, 'Job Title', _employeeDetail!['job_role'] ?? 'N/A', isDark, isHighContrast),
      ],
    );

    final workCard = _buildInfoCard(
      context,
      'Work Information',
      Icons.work_outline,
      isDark,
      isHighContrast,
      [
        _buildDetailRow(context, 'Target Daily Hours', '${_employeeDetail!['target_daily_hours'] ?? 0} hours', isDark, isHighContrast),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      basicInfoCard,
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    children: [
                      statusCard,
                      const SizedBox(height: 16),
                      orgCard,
                      const SizedBox(height: 16),
                      workCard,
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                basicInfoCard,
                const SizedBox(height: 16),
                statusCard,
                const SizedBox(height: 16),
                orgCard,
                const SizedBox(height: 16),
                workCard,
              ],
            ),
    );
  }

  Widget _buildInfoCard(
      BuildContext context,
      String title,
      IconData icon,
      bool isDark,
      bool isHighContrast,
      List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF182029) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF2D3643) : Colors.grey.shade200,
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
              Icon(icon, size: 20, color: Colors.blue),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          ...children.expand((w) => [w, const SizedBox(height: 12)]).toList()..removeLast(),
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
          width: 140,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 14,
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
              fontSize: 14,
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

  Color _getStatusColor(String status, bool isDark, bool isHighContrast) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
      case 'inactive':
        return Colors.red;
      default:
        return isDark
            ? (isHighContrast ? Colors.white : Colors.white)
            : Colors.black;
    }
  }

  String _getRecommendationTypeLabel(String type) {
    switch (type) {
      case 'SHORT_BREAK':
        return 'Short Break';
      case 'WALK':
        return 'Walk';
      case 'HYDRATE':
        return 'Hydrate';
      case 'STRETCH':
        return 'Stretch';
      case 'LUNCH':
        return 'Lunch';
      default:
        return type.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1).toLowerCase() : '').join(' ');
    }
  }

  Color _getRecommendationStatusColor(String? action, bool isDark, bool isHighContrast) {
    switch (action?.toLowerCase()) {
      case 'accepted':
        return Colors.green;
      case 'dismissed':
        return Colors.red;
      case 'ignored':
        return Colors.orange;
      default:
        return isDark
            ? (isHighContrast ? Colors.grey.shade600 : Colors.grey.shade600)
            : Colors.grey.shade400;
    }
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return 'Unknown';
    try {
      final date = DateTime.parse(timestamp);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp;
    }
  }

  String _formatWellbeingScore(dynamic score) {
    if (score == null) return 'N/A';
    return score.toString();
  }

  Widget _buildWorkSessionsTab(
      BuildContext context,
      bool isDark,
      bool isHighContrast) {
    if (!_isLoading && _workSessions.isEmpty) {
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
              'No Work Sessions Found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This employee has no completed work sessions.',
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

    // If we had actual work sessions data, we would display it here
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemCount: _workSessions.length,
      itemBuilder: (context, index) {
        final session = _workSessions[index];
        return ListTile(
          leading: const Icon(Icons.timer),
          title: Text(
            'Session ${index + 1}',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          subtitle: Text(
            '${session['start_time'] ?? 'N/A'} to ${session['end_time'] ?? 'N/A'}',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                  : Colors.grey.shade600,
            ),
          ),
          trailing: Text(
            '${session['duration_minutes'] ?? 0} min',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecommendationsTab(
      BuildContext context,
      bool isDark,
      bool isHighContrast) {
    // Loading state
    if (_recLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error state
    if (_recError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: isDark
                  ? (isHighContrast ? Colors.white : Colors.redAccent)
                  : Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Error Loading Recommendations',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _recError!,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Color(0xFF9AA3AF) : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadRecommendations,
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
      );
    }

    // Empty state
    if (_recommendations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 48,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.5)
                        : Color(0xFF9AA3AF))
                  : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No Recommendations Found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This employee has not received any recommendations yet.',
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

    // Show recommendations data
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _recommendations.length,
      itemBuilder: (context, index) {
        final recommendation = _recommendations[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          color: isDark ? const Color(0xFF2A2D3A) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Recommendation type and status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _getRecommendationTypeLabel(recommendation['recommendation_type']),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getRecommendationStatusColor(
                            recommendation['user_action'], isDark, isHighContrast),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        recommendation['user_action']?.toUpperCase() ?? 'PENDING',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Score and model info
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Score: ${(recommendation['recommendation_score'] * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Model: ${recommendation['model_version'] ?? 'Unknown'}',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Reason
                if (recommendation['reason'] != null)
                  Text(
                    'Reason: ${recommendation['reason']}',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                          : Colors.grey.shade600,
                    ),
                  ),
                const SizedBox(height: 8),
                // Timestamp
                Text(
                  'Generated: ${_formatTimestamp(recommendation['timestamp'])}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                        : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWellbeingTab(
      BuildContext context,
      bool isDark,
      bool isHighContrast) {
    // Loading state
    if (_wbLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error state
    if (_wbError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: isDark
                  ? (isHighContrast ? Colors.white : Colors.redAccent)
                  : Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Error Loading Wellbeing Data',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _wbError!,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Color(0xFF9AA3AF) : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadWellbeing,
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
      );
    }

    // Empty state
    if (_wellbeing.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.healing,
              size: 48,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.5)
                        : Color(0xFF9AA3AF))
                  : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No Wellbeing Check-ins Found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This employee has not completed any wellbeing check-ins yet.',
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

    // Show latest check-in and history
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Latest check-in section
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2D3A) : Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Latest Check-in',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              _buildWellbeingMetrics(
                _wellbeing.first,
                isDark,
                isHighContrast,
              ),
              const SizedBox(height: 12),
              if (_wellbeing.first['notes'] != null &&
                  _wellbeing.first['notes'].isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notes:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _wellbeing.first['notes'],
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        // Stress factors section (if any)
        if (_wellbeing.first['stress_factors'] != null &&
            (_wellbeing.first['stress_factors'] as List).isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2D3A) : Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stress Factors',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: (_wellbeing.first['stress_factors'] as List)
                      .map((factor) => Chip(
                            label: Text(
                              factor.toString(),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? (isHighContrast ? Colors.white : Colors.black)
                                    : Colors.black,
                              ),
                            ),
                            backgroundColor: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade200,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        // History section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2D3A) : Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Wellbeing History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              if (_wellbeing.length > 1)
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _wellbeing.length > 1 ? _wellbeing.length - 1 : 0,
                  itemBuilder: (context, index) {
                    final checkin = _wellbeing[index + 1]; // Skip first (latest)
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark
                              ? Colors.grey.shade600
                              : Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Overall: ${_formatWellbeingScore(checkin['overall_wellbeing'])}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Focus: ${_formatWellbeingScore(checkin['perceived_focus'])} | '
                                'Fatigue: ${_formatWellbeingScore(checkin['mental_fatigue'])}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            _formatTimestamp(checkin['created_at']),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? (isHighContrast ? Colors.white : Color(0xFF9AA3AF))
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              else
                const Text(
                  'No historical data available',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9AA3AF),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWellbeingMetrics(
      Map<String, dynamic> checkin, bool isDark, bool isHighContrast) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMetricRow('Overall Wellbeing',
            checkin['overall_wellbeing'], isDark, isHighContrast),
        const SizedBox(height: 8),
        _buildMetricRow('Mental Fatigue',
            checkin['mental_fatigue'], isDark, isHighContrast),
        const SizedBox(height: 8),
        _buildMetricRow('Workload Manageability',
            checkin['workload_manageability'], isDark, isHighContrast),
        const SizedBox(height: 8),
        _buildMetricRow('Perceived Focus',
            checkin['perceived_focus'], isDark, isHighContrast),
        const SizedBox(height: 8),
        _buildMetricRow('Break Recovery',
            checkin['break_recovery'], isDark, isHighContrast),
      ],
    );
  }

  Widget _buildMetricRow(
      String label, dynamic value, bool isDark, bool isHighContrast) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        Text(
          value?.toString() ?? 'N/A',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }
}