import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/admin/widgets/audit_action_helper.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuditLogsScreen extends StatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<dynamic> _auditLogs = [];
  String? _errorMessage;
  bool _auditLogsLoading = false;
  String? _auditLogsError;
  int _auditLogsPage = 1;
  final int _auditLogsLimit = 15;
  bool _hasMoreAuditLogs = true;
  Map<String, dynamic> _summaryData = {};
  bool _summaryLoading = false;
  String? _summaryError;

  // Filters
  String? _selectedActionType;
  String? _selectedCategory;
  String? _selectedOutcome;
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  List<dynamic> _actionTypes = [];

  String _selectedDatePreset = 'All Time';
  final List<String> _datePresets = [
    'All Time',
    'Today',
    'Yesterday',
    'This Week',
    'Last Week',
    'This Month',
    'Last Month',
    'Custom'
  ];

  final List<String> _categories = [
    'ACCOUNT',
    'TEAM',
    'ANALYTICS',
    'SECURITY',
    'SETTINGS',
    'SYSTEM'
  ];

  final List<String> _outcomes = [
    'SUCCESS',
    'FAILURE',
    'PENDING'
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });

        _updateDateRangeFromPreset();
        _loadAuditLogs(token, refresh: true);
        _loadAuditSummary(token);
        _loadAuditFilters(token);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    } else {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'No authentication token found';
      });
    }
  }

  void _updateDateRangeFromPreset() {
    final now = DateTime.now();
    switch (_selectedDatePreset) {
      case 'All Time':
        _startDate = null;
        _endDate = null;
        break;
      case 'Today':
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        break;
      case 'Yesterday':
        final yesterday = now.subtract(const Duration(days: 1));
        _startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
        _endDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59, 999);
        break;
      case 'This Week':
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        _startDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        break;
      case 'Last Week':
        final startOfLastWeek = now.subtract(Duration(days: now.weekday + 6));
        _startDate = DateTime(startOfLastWeek.year, startOfLastWeek.month, startOfLastWeek.day);
        final endOfLastWeek = startOfLastWeek.add(const Duration(days: 6));
        _endDate = DateTime(endOfLastWeek.year, endOfLastWeek.month, endOfLastWeek.day, 23, 59, 59, 999);
        break;
      case 'This Month':
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month,
            DateTime(now.year, now.month + 1, 0).day, 23, 59, 59, 999);
        break;
      case 'Last Month':
        final lastMonth = DateTime(now.year, now.month - 1);
        _startDate = DateTime(lastMonth.year, lastMonth.month, 1);
        _endDate = DateTime(lastMonth.year, lastMonth.month,
            DateTime(lastMonth.year, lastMonth.month + 1, 0).day, 23, 59, 59, 999);
        break;
      case 'Custom':
        break;
    }
  }

  Future<void> _loadAuditFilters(String token) async {
    _actionTypes = [
      {'id': 'USER_CREATED', 'name': 'User Created'},
      {'id': 'USER_APPROVED', 'name': 'User Approved'},
      {'id': 'USER_REJECTED', 'name': 'User Rejected'},
      {'id': 'TEAM_CREATED', 'name': 'Team Created'},
      {'id': 'TEAM_UPDATED', 'name': 'Team Updated'},
      {'id': 'TEAM_DELETED', 'name': 'Team Deleted'},
      {'id': 'WORK_SESSION_STARTED', 'name': 'Work Session Started'},
      {'id': 'WORK_SESSION_ENDED', 'name': 'Work Session Ended'},
      {'id': 'TASK_CREATED', 'name': 'Task Created'},
      {'id': 'LOGIN', 'name': 'Login'},
      {'id': 'LOGOUT', 'name': 'Logout'},
    ];
    if (mounted) setState(() {});
  }

  Future<void> _loadAuditSummary(String token) async {
    setState(() {
      _summaryLoading = true;
      _summaryError = null;
    });
    try {
      final summary = await _apiService.getAuditLogsSummary(
        token,
        actionType: _selectedActionType,
        category: _selectedCategory,
        outcome: _selectedOutcome,
        startDate: _startDate,
        endDate: _endDate,
        search: _searchText.isNotEmpty ? _searchText : null,
      );
      if (!mounted) return;
      setState(() {
        _summaryLoading = false;
        _summaryData = summary;
        _summaryError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryLoading = false;
        _summaryError = e.toString();
      });
    }
  }

  Future<void> _loadAuditLogs(String token, {bool refresh = false}) async {
    if (_auditLogsLoading) return;

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

      final auditLogs = await _apiService.getAuditLogs(
        token,
        page: _auditLogsPage,
        limit: _auditLogsLimit,
        actionType: _selectedActionType,
        category: _selectedCategory,
        outcome: _selectedOutcome,
        startDate: _startDate,
        endDate: _endDate,
        search: _searchText.isNotEmpty ? _searchText : null,
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

  Future<void> _refreshData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null) {
      await _loadAuditLogs(token, refresh: true);
      await _loadAuditSummary(token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context).isHighContrast;

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorView(isDark, isHighContrast)
              : _buildAuditLogsView(isDark, isHighContrast),
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
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 24),
            const Text('Error Loading Audit Logs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Text(_errorMessage ?? 'An unknown error occurred', textAlign: TextAlign.center),
            const SizedBox(height: 32),
            ElevatedButton(onPressed: _refreshData, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditLogsView(bool isDark, bool isHighContrast) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header & Toolbar Card
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: isDark ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF151A21)) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Security Audit Logs', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Comprehensive administrative and system event audit trail.',
                            style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey.shade600)),
                      ],
                    ),
                    Text('${_auditLogs.length} events loaded', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
                const SizedBox(height: 16),
                _buildFilterToolbar(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Summary KPI Cards
          _buildKpiCards(isDark, isHighContrast),
          const SizedBox(height: 16),
          // Data Table Container
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF151A21)) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: _auditLogsError != null
                  ? Center(child: Text('Error loading logs: $_auditLogsError', style: const TextStyle(color: Colors.red)))
                  : _auditLogs.isEmpty && _auditLogsLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _auditLogs.isEmpty
                          ? const Center(child: Text('No audit logs found matching criteria.'))
                          : _buildDataTable(isDark, isHighContrast),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterToolbar() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        // Search field
        SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Search', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Action, target, summary...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                ),
                onChanged: (val) {
                  _searchText = val;
                },
              ),
            ],
          ),
        ),
        // Date Preset
        SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Date Preset', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _selectedDatePreset,
                items: _datePresets.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedDatePreset = val;
                      if (val != 'Custom') _updateDateRangeFromPreset();
                    });
                  }
                },
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true),
              ),
            ],
          ),
        ),
        // Category Filter
        SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Category', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Categories', style: TextStyle(fontSize: 13))),
                  ..._categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)))),
                ],
                onChanged: (val) => setState(() => _selectedCategory = val),
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true),
              ),
            ],
          ),
        ),
        // Outcome Filter
        SizedBox(
          width: 130,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Outcome', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _selectedOutcome,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Outcomes', style: TextStyle(fontSize: 13))),
                  ..._outcomes.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13)))),
                ],
                onChanged: (val) => setState(() => _selectedOutcome = val),
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true),
              ),
            ],
          ),
        ),
        // Action Type Filter
        SizedBox(
          width: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Action Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _selectedActionType,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Actions', style: TextStyle(fontSize: 13))),
                  ..._actionTypes.map((item) => DropdownMenuItem(value: item['id'] as String, child: Text(item['name'] as String, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (val) => setState(() => _selectedActionType = val),
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true),
              ),
            ],
          ),
        ),
        // Buttons
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: () async {
                final token = await _apiService.getToken();
                if (token != null) {
                  _loadAuditLogs(token, refresh: true);
                  _loadAuditSummary(token);
                }
              },
              icon: const Icon(Icons.filter_list, size: 16),
              label: const Text('Apply'),
              style: ElevatedButton.styleFrom(backgroundColor: DesignSystem.getSemanticColor(context, SemanticColor.primary)),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                setState(() {
                  _selectedActionType = null;
                  _selectedCategory = null;
                  _selectedOutcome = null;
                  _selectedDatePreset = 'All Time';
                  _updateDateRangeFromPreset();
                  _searchController.clear();
                  _searchText = '';
                });
                final token = await _apiService.getToken();
                if (token != null) {
                  _loadAuditLogs(token, refresh: true);
                  _loadAuditSummary(token);
                }
              },
              child: const Text('Clear'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCards(bool isDark, bool isHighContrast) {
    if (_summaryError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Failed to load summary metrics: $_summaryError', style: const TextStyle(color: Colors.red, fontSize: 13))),
          ],
        ),
      );
    }

    final total = _summaryLoading ? '...' : (_summaryData['total_events']?.toString() ?? '0');
    final authSec = _summaryLoading ? '...' : (_summaryData['auth_security_events']?.toString() ?? '0');
    final failed = _summaryLoading ? '...' : (_summaryData['failed_events']?.toString() ?? '0');

    final earliest = _summaryData['earliest_date'];
    final latest = _summaryData['latest_date'];
    String spanText = 'All Time';
    if (_summaryLoading) {
      spanText = '...';
    } else if (earliest != null && latest != null) {
      spanText = '${_formatDateOnly(earliest)} - ${_formatDateOnly(latest)}';
    } else if (earliest != null) {
      spanText = 'From ${_formatDateOnly(earliest)}';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        int crossAxisCount = 4;
        if (width < 600) {
          crossAxisCount = 1;
        } else if (width < 1000) {
          crossAxisCount = 2;
        }

        final cards = [
          _kpiCard(context, 'Total Audit Events', total, Icons.receipt_long, Colors.blue, isDark, isHighContrast),
          _kpiCard(context, 'Auth & Security', authSec, Icons.security, Colors.purple, isDark, isHighContrast),
          _kpiCard(context, 'Failed Events', failed, Icons.warning_amber_rounded, (int.tryParse(failed) ?? 0) > 0 ? Colors.red : Colors.green, isDark, isHighContrast),
          _kpiCard(context, 'Audit Trail Span', spanText, Icons.date_range, Colors.teal, isDark, isHighContrast),
        ];

        if (crossAxisCount == 4) {
          return Row(
            children: cards.asMap().entries.map((entry) {
              final index = entry.key;
              final card = entry.value;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index < cards.length - 1 ? 12.0 : 0.0),
                  child: card,
                ),
              );
            }).toList(),
          );
        } else if (crossAxisCount == 2) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: Padding(padding: const EdgeInsets.only(right: 6, bottom: 12), child: cards[0])),
                  Expanded(child: Padding(padding: const EdgeInsets.only(left: 6, bottom: 12), child: cards[1])),
                ],
              ),
              Row(
                children: [
                  Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: cards[2])),
                  Expanded(child: Padding(padding: const EdgeInsets.only(left: 6), child: cards[3])),
                ],
              ),
            ],
          );
        } else {
          return Column(
            children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: c)).toList(),
          );
        }
      },
    );
  }

  Widget _kpiCard(BuildContext context, String title, String value, IconData icon, Color color, bool isDark, bool isHighContrast) {
    return Container(
      width: double.infinity,
      height: 96,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF151A21)) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateOnly(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (e) {
      return '';
    }
  }

  Widget _buildDataTable(bool isDark, bool isHighContrast) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (_auditLogsLoading || !_hasMoreAuditLogs) return false;
        if (notification.metrics.pixels >= notification.metrics.maxScrollExtent * 0.85) {
          _loadMoreLogs();
        }
        return false;
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100),
            columns: const [
              DataColumn(label: Text('Timestamp', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Actor', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Target / Resource', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Outcome', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Summary', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Details', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: _auditLogs.map((log) {
              final formattedDate = _formatTimestamp(log['created_at']);
              final actionTitle = readableActionTitle(log['action_type'] ?? '');
              final category = log['category'] ?? 'SYSTEM';
              final actor = log['user_full_name'] ?? log['user_email'] ?? 'System';
              final target = log['target_display_label'] ?? log['target_id'] ?? log['action_details']?['target_name'] ?? '-';
              final outcome = log['outcome'] ?? 'SUCCESS';
              final summary = log['summary'] ?? actionTitle;

              Color outcomeColor = Colors.green;
              if (outcome == 'FAILURE' || outcome == 'ERROR') outcomeColor = Colors.red;
              if (outcome == 'PENDING') outcomeColor = Colors.orange;

              Color categoryColor = Colors.blue;
              if (category == 'SECURITY' || category == 'AUTHENTICATION') categoryColor = Colors.purple;
              if (category == 'TEAM') categoryColor = Colors.orange;
              if (category == 'DATA_ACCESS') categoryColor = Colors.teal;
              if (category == 'ACCOUNT') categoryColor = Colors.indigo;
              if (category == 'SETTINGS') categoryColor = Colors.amber.shade700;
              if (category == 'SYSTEM') categoryColor = Colors.grey;

              return DataRow(cells: [
                DataCell(Text(formattedDate, style: const TextStyle(fontSize: 12))),
                DataCell(
                  Tooltip(
                    message: log['action_type'] ?? '',
                    child: Text(actionTitle, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(category, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: categoryColor)),
                  ),
                ),
                DataCell(Text(actor, style: const TextStyle(fontSize: 12))),
                DataCell(Text(target.toString(), style: const TextStyle(fontSize: 12))),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: outcomeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(outcome, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: outcomeColor)),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 220,
                    child: Text(summary, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(
                  TextButton.icon(
                    onPressed: () => _showEventDetailDialog(log),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('View'),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  ),
                ),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null) return '-';
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoString;
    }
  }

  void _loadMoreLogs() async {
    final token = await _apiService.getToken();
    if (token != null) {
      await _loadAuditLogs(token);
    }
  }

  void _showEventDetailDialog(dynamic log) {
    final details = log['action_details'] is Map ? log['action_details'] as Map : <String, dynamic>{};
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.security, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(readableActionTitle(log['action_type'] ?? ''), style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Event ID', log['id'] ?? '-'),
                _detailRow('Action Type', log['action_type'] ?? '-'),
                _detailRow('Category', log['category'] ?? '-'),
                _detailRow('Outcome', log['outcome'] ?? '-'),
                _detailRow('Timestamp', _formatTimestamp(log['created_at'])),
                _detailRow('Actor', '${log['user_full_name'] ?? 'System'} (${log['user_email'] ?? 'N/A'})'),
                _detailRow('Target Type', log['target_type'] ?? '-'),
                _detailRow('Target ID', log['target_id'] ?? '-'),
                _detailRow('Target Display', log['target_display_label'] ?? '-'),
                _detailRow('Summary', log['summary'] ?? '-'),
                _detailRow('IP Address', log['ip_address'] ?? 'N/A'),
                _detailRow('User Agent', log['user_agent'] ?? 'N/A'),
                const Divider(height: 24),
                const Text('Structured Details / Payload:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                if (details.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: const Text('Legacy event: Recorded without an expanded detail payload.', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
                  )
                else
                  ...details.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 140, child: Text('${e.key}:', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
                            Expanded(child: Text('${e.value}', style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text('$label:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade600, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
