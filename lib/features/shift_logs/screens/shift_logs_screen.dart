import 'package:flutter/material.dart';
import 'package:intellibreak/features/shift_logs/widgets/recommendation_history_dialog.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/dashboard/services/work_service.dart';
import 'package:intellibreak/widgets/state_display.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShiftLogsScreen extends StatefulWidget {
  const ShiftLogsScreen({super.key});

  @override
  State<ShiftLogsScreen> createState() => _ShiftLogsScreenState();
}

class _ShiftLogsScreenState extends State<ShiftLogsScreen> {
  final WorkService _workService = WorkService();

  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _filteredSessions = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Filter state
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _statusFilter = 'All'; // All, Completed, Active
  String _searchQuery = '';

  // Available filter options
  final List<String> _statusFilters = ['All', 'Completed', 'Active'];

  // Date range presets
  String _dateRangePreset = 'All Time'; // All Time, Today, Yesterday, Last 7 Days, Last 30 Days, Custom

  @override
  void initState() {
    super.initState();
    _loadShiftHistory();
  }

  Future<void> _loadShiftHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null) {
        // No token -> show empty state (guest users should be routed to DemoShell via AuthGate)
        if (!mounted) return;
        setState(() {
          _sessions = [];
          _isLoading = false;
        });
        return;
      }

      // Authenticated mode - load from backend
      final response = await _workService.getSessionsHistory(token);

      if (!mounted) return;
      setState(() {
        _sessions = List<Map<String, dynamic>>.from(response);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load shift history: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    if (!mounted) return;

    List<Map<String, dynamic>> filtered = List.from(_sessions);

    // Date range filter from preset
    if (_dateRangePreset != 'All Time') {
      final now = DateTime.now();
      DateTime? startDate;
      DateTime? endDate;

      switch (_dateRangePreset) {
        case 'Today':
          startDate = DateTime(now.year, now.month, now.day);
          endDate = now;
          break;
        case 'Yesterday':
          final yesterday = now.subtract(const Duration(days: 1));
          startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
          endDate = now
              .subtract(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1));
          break;
        case 'Last 7 Days':
          startDate = now.subtract(const Duration(days: 7));
          endDate = now;
          break;
        case 'Last 30 Days':
          startDate = now.subtract(const Duration(days: 30));
          endDate = now;
          break;
        case 'Custom':
          // Use manual date range
          break;
        default:
          // All Time - no filter
          break;
      }

      if (startDate != null && endDate != null) {
        filtered = filtered.where((session) {
          final startedAt = DateTime.parse(session['started_at']).toLocal();
          return startedAt.isAfter(
                startDate!.subtract(const Duration(milliseconds: 1)),
              ) &&
              startedAt.isBefore(endDate!.add(const Duration(days: 1)));
        }).toList();
      } else {
        // Handle custom range
        if (_dateFrom != null) {
          filtered = filtered.where((session) {
            final startedAt = DateTime.parse(session['started_at']).toLocal();
            return startedAt.isAtSameMomentAs(_dateFrom!) ||
                startedAt.isAfter(_dateFrom!);
          }).toList();
        }

        if (_dateTo != null) {
          filtered = filtered.where((session) {
            final startedAt = DateTime.parse(session['started_at']).toLocal();
            return startedAt.isAtSameMomentAs(_dateTo!) ||
                startedAt.isBefore(_dateTo!);
          }).toList();
        }
      }
    } else {
      // Handle custom range when preset is 'Custom'
      if (_dateFrom != null) {
        filtered = filtered.where((session) {
          final startedAt = DateTime.parse(session['started_at']).toLocal();
          return startedAt.isAtSameMomentAs(_dateFrom!) ||
              startedAt.isAfter(_dateFrom!);
        }).toList();
      }

      if (_dateTo != null) {
        filtered = filtered.where((session) {
          final startedAt = DateTime.parse(session['started_at']).toLocal();
          return startedAt.isAtSameMomentAs(_dateTo!) ||
              startedAt.isBefore(_dateTo!);
        }).toList();
      }
    }

    // Status filter
    if (_statusFilter != 'All') {
      filtered = filtered.where((session) {
        final endedAt = session['ended_at'];
        final isActive = endedAt == null;

        if (_statusFilter == 'Completed') {
          return !isActive;
        } else if (_statusFilter == 'Active') {
          return isActive;
        }
        return false;
      }).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final queryLower = _searchQuery.toLowerCase();
      filtered = filtered.where((session) {
        // Search in tasks title and category
        final tasks = List<Map<String, dynamic>>.from(session['tasks'] ?? []);
        final matchesTask = tasks.any((task) {
          final title = (task['title'] ?? '').toLowerCase();
          final category = (task['category'] ?? '').toLowerCase();
          return title.contains(queryLower) || category.contains(queryLower);
        });

        // Also search in break types
        final breaks = List<Map<String, dynamic>>.from(session['breaks'] ?? []);
        final matchesBreak = breaks.any((brk) {
          final breakType = (brk['break_type'] ?? '').toLowerCase();
          return breakType.contains(queryLower);
        });

        return matchesTask || matchesBreak;
      }).toList();
    }

    // Employee filter (placeholder for future implementation)
    // For now, we only show the current user's sessions in guest/demo mode
    // In authenticated mode, this would filter by specific employee for managers/admins

    setState(() {
      _filteredSessions = filtered;
    });
  }

  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 1100;

    return _buildBody(context, isDark, isDesktop);
  }

  Widget _buildBody(BuildContext context, bool isDark, bool isDesktop) {
  return StateDisplay(
    isLoading: _isLoading,
    errorMessage: _errorMessage,
    isEmpty: _sessions.isEmpty,
    content: RefreshIndicator(
      onRefresh: _loadShiftHistory,
      child: isDesktop
          ? _buildDesktopLayout(context, isDark)
          : _buildMobileLayout(context, isDark),
    ),
    onRetry: _loadShiftHistory,
    loadingMessage: 'Loading your shift history...',
    emptyMessage: 'No shift history yet',
    emptyAction: ElevatedButton(
      onPressed: () {
        // For shift logs, we might want to suggest starting a shift
        // But since the action would be context-dependent, we'll keep it simple
        // or potentially make it a button to clear filters if that's relevant
      },
      child: const Text('Start a shift'),
    ),
  );
}

  Widget _buildDesktopLayout(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Metrics Card
          _buildSummaryMetricsCard(context, isDark),
          const SizedBox(height: 32),

          // Recent Shifts Section
          Text(
            'Recent Shifts',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildRecentShiftsSection(context, isDark),
          const SizedBox(height: 32),

          // Shift History Section
          Text(
            'Shift History',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildHistoryFilters(context, isDark, true),
          const SizedBox(height: 24),
          _buildHistoryTable(context, isDark),
        ],
      ),
    );
  }

  Widget _buildRecentShiftsSection(BuildContext context, bool isDark) {
    // Show most recent 3-5 shifts (newest first)
    final recentSessions = _filteredSessions.take(5).toList()
      ..sort((a, b) {
        final dateA = DateTime.parse(a['started_at']);
        final dateB = DateTime.parse(b['started_at']);
        return dateB.compareTo(dateA); // Newest first
      });

    if (recentSessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No recent shifts',
          style: TextStyle(
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: DesignSystem.getSemanticColor(context, SemanticColor.surface),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(2),
          3: FlexColumnWidth(2),
          4: FlexColumnWidth(2),
          5: FlexColumnWidth(2),
          6: FlexColumnWidth(2),
        },
        children: [
          // Header row
          TableRow(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.onSurfaceVariant,
                  ).withValues(alpha: 0.2),
                ),
              ),
            ),
            children: [
              _buildTableHeader(context, 'Date'),
              _buildTableHeader(context, 'Start Time'),
              _buildTableHeader(context, 'End Time'),
              _buildTableHeader(context, 'Duration'),
              _buildTableHeader(context, 'Breaks'),
              _buildTableHeader(context, 'Tasks'),
              _buildTableHeader(context, 'Recommendations'),
            ],
          ),
          // Data rows
          ...recentSessions.map(
            (session) => _buildTableRow(context, isDark, session),
          ),
        ],
      ),
    );
  }

  TableRow _buildTableRow(
    BuildContext context,
    bool isDark,
    Map<String, dynamic> session,
  ) {
    final startedAt = DateTime.parse(session['started_at']).toLocal();
    final endedAt = session['ended_at'] != null
        ? DateTime.parse(session['ended_at']).toLocal()
        : null;
    final durationMinutes = session['duration_minutes'] ?? 0;
    final breaks = List<Map<String, dynamic>>.from(session['breaks'] ?? []);
    final tasks = List<Map<String, dynamic>>.from(session['tasks'] ?? []);

    return TableRow(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.onSurfaceVariant,
            ).withValues(alpha: 0.1),
          ),
        ),
      ),
      children: [
        _buildTableCell(context, _formatDate(startedAt)),
        _buildTableCell(context, _formatTime(startedAt)),
        _buildTableCell(context, endedAt != null ? _formatTime(endedAt) : '-'),
        _buildTableCell(context, _formatDuration(durationMinutes)),
        _buildTableCell(
          context,
          '${breaks.length} breaks (${_calculateTotalBreakMinutes(breaks)} min)',
        ),
        _buildTasksCell(context, tasks),
        _buildRecommendationsCell(context, session['id']?.toString() ?? ''),
      ],
    );
  }

  Widget _buildRecommendationsCell(BuildContext context, String sessionId) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => RecommendationHistoryDialog(
              workSessionId: sessionId,
              sessionLabel: 'Session $sessionId',
            ),
          );
        },
        child: const Text('View'),
      ),
    );
  }

  Widget _buildHistoryFilters(
    BuildContext context,
    bool isDark,
    bool isDesktop,
  ) {
    // Build the shared controls once so both layouts reuse the same behavior.
    final dateRange = _buildFilterDropdown(
      context,
      'Date Range',
      _dateRangePreset,
      [
        'All Time',
        'Today',
        'Yesterday',
        'Last 7 Days',
        'Last 30 Days',
        'Custom',
      ],
      (value) {
        setState(() {
          _dateRangePreset = value!;
          // Reset custom dates when switching presets
          if (value != 'Custom') {
            _dateFrom = null;
            _dateTo = null;
          }
          _applyFilters();
        });
      },
      isDark,
    );

    final search = _buildSearchField(context, isDark);

    final status = _buildFilterDropdown(
      context,
      'Status',
      _statusFilter,
      _statusFilters,
      (value) {
        setState(() {
          _statusFilter = value!;
          _applyFilters();
        });
      },
      isDark,
    );

    final applyButton = _buildApplyButton(context);
    final clearButton = _buildClearButton(context);

    // Custom date range row (only when the Custom preset is selected).
    final customDateRow = _dateRangePreset == 'Custom'
        ? Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildDatePicker(context, 'From', _dateFrom, (date) {
                    setState(() {
                      _dateFrom = date;
                      _applyFilters();
                    });
                  }, isDark),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildDatePicker(context, 'To', _dateTo, (date) {
                    setState(() {
                      _dateTo = date;
                      _applyFilters();
                    });
                  }, isDark),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: DesignSystem.getSemanticColor(context, SemanticColor.surface),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (isDesktop)
            // Compact, balanced single-row toolbar for desktop.
            // Fixed widths keep proportions intentional; Search flexes but is
            // capped so it never dwarfs the other controls. Buttons are pushed
            // down by the label height so they align with the input fields.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 200, child: dateRange),
                const SizedBox(width: 16),
                Flexible(
                  fit: FlexFit.loose,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: search,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(width: 160, child: status),
                const SizedBox(width: 16),
                _buildToolbarButton(applyButton),
                const SizedBox(width: 12),
                _buildToolbarButton(clearButton),
              ],
            )
          else
            // Compact responsive layout for mobile/tablet.
            Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: dateRange),
                    const SizedBox(width: 12),
                    Expanded(child: status),
                  ],
                ),
                const SizedBox(height: 12),
                search,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: applyButton),
                    const SizedBox(width: 12),
                    Expanded(child: clearButton),
                  ],
                ),
              ],
            ),
          customDateRow,
        ],
      ),
    );
  }

  Widget _buildApplyButton(BuildContext context) {
    return ElevatedButton(
      onPressed: _applyFilters,
      style: ElevatedButton.styleFrom(
        backgroundColor: DesignSystem.getSemanticColor(
          context,
          SemanticColor.primary,
        ),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      child: const Text('Apply'),
    );
  }

  Widget _buildClearButton(BuildContext context) {
    return OutlinedButton(
      onPressed: _clearFilters,
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: DesignSystem.getSemanticColor(
            context,
            SemanticColor.onSurfaceVariant,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      child: const Text('Clear'),
    );
  }

  /// Wraps a toolbar button so its baseline aligns with the input fields'
  /// baselines. Input fields have a 14px label + 8px gap = 22px above the
  /// field. Buttons have no label, so we add equivalent top padding.
  Widget _buildToolbarButton(Widget button) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: SizedBox(width: 96, child: button),
    );
  }

  Widget _buildFilterDropdown<T>(
    BuildContext context,
    String label,
    T currentValue,
    List<T> options,
    ValueChanged<T?> onChanged,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.background,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurfaceVariant,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              isDense: true,
              isExpanded: true,
              value: currentValue,
              onChanged: onChanged,
              items: options.map((option) {
                return DropdownMenuItem<T>(
                  value: option,
                  child: Text(
                    option.toString(),
                    style: TextStyle(
                      color: DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.onSurface,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(
    BuildContext context,
    String label,
    DateTime? selectedDate,
    ValueChanged<DateTime?> onChanged,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.background,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurfaceVariant,
              ),
            ),
          ),
          child: TextButton(
            onPressed: () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: selectedDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                onChanged(picked);
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  selectedDate == null
                      ? 'Select date'
                      : '${selectedDate.month}/${selectedDate.day}/${selectedDate.year}',
                  style: TextStyle(
                    color: DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.onSurface,
                    ),
                  ),
                ),
                Icon(
                  Icons.calendar_today,
                  size: 20,
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Search',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.background,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurfaceVariant,
              ),
            ),
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search tasks, breaks...',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              prefixIcon: Icon(
                Icons.search,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ),
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _applyFilters();
              });
            },
          ),
        ),
      ],
    );
  }

  void _clearFilters() {
    setState(() {
      _dateRangePreset = 'All Time';
      _dateFrom = null;
      _dateTo = null;
      _statusFilter = 'All';
      _searchQuery = '';
      _applyFilters();
    });
  }

  Widget _buildHistoryTable(BuildContext context, bool isDark) {
    if (_filteredSessions.isEmpty) {
      return _buildEmptyState(context);
    }

    // Group sessions by time period
    final groupedSessions = _groupSessionsByPeriod(_filteredSessions);

    return Container(
      decoration: BoxDecoration(
        color: DesignSystem.getSemanticColor(context, SemanticColor.surface),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: groupedSessions.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.onSurface,
                    ),
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ).withValues(alpha: 0.2),
              ),
              ...entry.value.map(
                (session) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: _buildHistoryTableRow(context, isDark, session),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 48,
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurfaceVariant,
              ).withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No shifts found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your filters',
              style: TextStyle(
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _clearFilters,
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.primary,
                ),
                foregroundColor: Colors.white,
              ),
              child: const Text('Clear Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupSessionsByPeriod(
    List<Map<String, dynamic>> sessions,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastWeek = today.subtract(const Duration(days: 7));
    final lastMonth = today.subtract(const Duration(days: 30));

    final groups = <String, List<Map<String, dynamic>>>{
      'Yesterday': [],
      'Last 7 Days': [],
      'Last 30 Days': [],
      'Older': [],
    };

    for (final session in sessions) {
      final startedAt = DateTime.parse(session['started_at']).toLocal();
      final sessionDate = DateTime(
        startedAt.year,
        startedAt.month,
        startedAt.day,
      );

      if (sessionDate.isAtSameMomentAs(yesterday)) {
        groups['Yesterday']!.add(session);
      } else if (sessionDate.isAfter(yesterday) &&
          sessionDate.isBefore(lastWeek.add(const Duration(days: 1)))) {
        groups['Last 7 Days']!.add(session);
      } else if (sessionDate.isAfter(lastWeek) &&
          sessionDate.isBefore(lastMonth.add(const Duration(days: 1)))) {
        groups['Last 30 Days']!.add(session);
      } else {
        groups['Older']!.add(session);
      }
    }

    // Remove empty groups
    groups.removeWhere((key, value) => value.isEmpty);

    return groups;
  }

  Widget _buildHistoryTableRow(
    BuildContext context,
    bool isDark,
    Map<String, dynamic> session,
  ) {
    final startedAt = DateTime.parse(session['started_at']).toLocal();
    final endedAt = session['ended_at'] != null
        ? DateTime.parse(session['ended_at']).toLocal()
        : null;
    final durationMinutes = session['duration_minutes'] ?? 0;
    final breaks = List<Map<String, dynamic>>.from(session['breaks'] ?? []);
    final tasks = List<Map<String, dynamic>>.from(session['tasks'] ?? []);

    return InkWell(
      onTap: () => _showSessionDetailDialog(context, session),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurfaceVariant,
              ).withValues(alpha: 0.1),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildTableCell(context, _formatDate(startedAt)),
            ),
            Expanded(
              flex: 2,
              child: _buildTableCell(context, _formatTime(startedAt)),
            ),
            Expanded(
              flex: 2,
              child: _buildTableCell(
                context,
                endedAt != null ? _formatTime(endedAt) : '-',
              ),
            ),
            Expanded(
              flex: 2,
              child: _buildTableCell(context, _formatDuration(durationMinutes)),
            ),
            Expanded(
              flex: 2,
              child: _buildTableCell(
                context,
                '${breaks.length} breaks (${_calculateTotalBreakMinutes(breaks)} min)',
              ),
            ),
            Expanded(
              flex: 3,
              child: _buildTasksCell(context, tasks),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: TextButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => RecommendationHistoryDialog(
                        workSessionId: session['id']?.toString() ?? '',
                        sessionLabel: 'Session ${session['id']?.toString() ?? ''}',
                      ),
                    );
                  },
                  child: const Text('View'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Reuse existing methods from original code
  Widget _buildTableHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: DesignSystem.getSemanticColor(
            context,
            SemanticColor.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildTableCell(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: DesignSystem.getSemanticColor(
            context,
            SemanticColor.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildTasksCell(
    BuildContext context,
    List<Map<String, dynamic>> tasks,
  ) {
    if (tasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No tasks',
          style: TextStyle(
            fontSize: 14,
            color: DesignSystem.getSemanticColor(
              context,
              SemanticColor.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...tasks.take(3).map((task) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• ${task['title']} (${task['category'] ?? 'General'})',
                style: TextStyle(
                  fontSize: 13,
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.onSurface,
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
          if (tasks.length > 3)
            Text(
              '  +${tasks.length - 3} more',
              style: TextStyle(
                fontSize: 12,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDateFull(DateTime date) {
    final weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12
        ? time.hour - 12
        : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  int _calculateTotalBreakMinutes(List<Map<String, dynamic>> breaks) {
    return breaks.fold(
      0,
      (sum, break_) => sum + (break_['duration_minutes'] as int? ?? 0),
    );
  }

  Widget _buildSummaryMetricsCard(BuildContext context, bool isDark) {
    int totalSessions = _filteredSessions.length;
    int totalWorkingMinutes = 0;
    int totalBreaksCount = 0;
    int totalBreakMinutes = 0;

    for (var s in _filteredSessions) {
      totalWorkingMinutes += (s['duration_minutes'] as int?) ?? 0;
      final breaks = List<Map<String, dynamic>>.from(s['breaks'] ?? []);
      totalBreaksCount += breaks.length;
      totalBreakMinutes += _calculateTotalBreakMinutes(breaks);
    }

    final avgSessionMin = totalSessions > 0 ? (totalWorkingMinutes ~/ totalSessions) : 0;
    final avgBreakMin = totalBreaksCount > 0 ? (totalBreakMinutes ~/ totalBreaksCount) : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DesignSystem.getSemanticColor(context, SemanticColor.surface),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Summary Metrics',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildMetricTile(context, 'Total Sessions', '$totalSessions', Icons.work_outline),
              _buildMetricTile(context, 'Total Work Time', _formatDuration(totalWorkingMinutes), Icons.timer_outlined),
              _buildMetricTile(context, 'Avg Session', _formatDuration(avgSessionMin), Icons.hourglass_empty),
              _buildMetricTile(context, 'Total Break Time', _formatDuration(totalBreakMinutes), Icons.coffee_outlined),
              _buildMetricTile(context, 'Avg Break', _formatDuration(avgBreakMin), Icons.coffee),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(BuildContext context, String label, String value, IconData icon) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DesignSystem.getSemanticColor(context, SemanticColor.background),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: DesignSystem.getSemanticColor(context, SemanticColor.primary)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  void _showSessionDetailDialog(BuildContext context, Map<String, dynamic> session) {
    final startedAt = DateTime.parse(session['started_at']).toLocal();
    final endedAt = session['ended_at'] != null ? DateTime.parse(session['ended_at']).toLocal() : null;
    final durationMinutes = session['duration_minutes'] ?? 0;
    final breaks = List<Map<String, dynamic>>.from(session['breaks'] ?? []);
    final tasks = List<Map<String, dynamic>>.from(session['tasks'] ?? []);
    final sessionId = session['id']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Session Details — ${_formatDate(startedAt)}'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Overview', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                Text('Start Time: ${_formatTime(startedAt)}'),
                Text('End Time: ${endedAt != null ? _formatTime(endedAt) : 'Active'}'),
                Text('Duration: ${_formatDuration(durationMinutes)}'),
                Text('Status: ${endedAt != null ? 'Completed' : 'Active'}'),
                const Divider(height: 24),

                Text('Break Timeline (${breaks.length} breaks)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                if (breaks.isEmpty)
                  const Text('No breaks recorded for this session.')
                else
                  ...breaks.map((b) {
                    final bStart = DateTime.parse(b['started_at']).toLocal();
                    final bEnd = b['ended_at'] != null ? DateTime.parse(b['ended_at']).toLocal() : null;
                    final bMin = b['duration_minutes'] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• ${b['break_type']}: ${_formatTime(bStart)} - ${bEnd != null ? _formatTime(bEnd) : 'Active'} ($bMin min)'),
                    );
                  }),
                const Divider(height: 24),

                Text('Associated Tasks (${tasks.length} tasks)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                if (tasks.isEmpty)
                  const Text('No tasks associated with this session.')
                else
                  ...tasks.map((t) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• ${t['title']} [${t['status']}] (${t['actual_minutes'] ?? 0} min)'),
                    );
                  }),
                const Divider(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('AI Recommendations', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    TextButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => RecommendationHistoryDialog(
                            workSessionId: sessionId,
                            sessionLabel: 'Session $sessionId',
                          ),
                        );
                      },
                      child: const Text('View Recommendations'),
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
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredSessions.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildSummaryMetricsCard(context, isDark),
          );
        }
        final session = _filteredSessions[index - 1];
        return _buildMobileSessionCard(context, isDark, session);
      },
    );
  }

  Widget _buildMobileSessionCard(
    BuildContext context,
    bool isDark,
    Map<String, dynamic> session,
  ) {
    final startedAt = DateTime.parse(session['started_at']).toLocal();
    final endedAt = session['ended_at'] != null
        ? DateTime.parse(session['ended_at']).toLocal()
        : null;
    final durationMinutes = session['duration_minutes'] ?? 0;
    final breaks = List<Map<String, dynamic>>.from(session['breaks'] ?? []);
    final tasks = List<Map<String, dynamic>>.from(session['tasks'] ?? []);

    return InkWell(
      onTap: () => _showSessionDetailDialog(context, session),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DesignSystem.getSemanticColor(context, SemanticColor.surface),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDateFull(startedAt),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.primary,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _formatDuration(durationMinutes),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Time info
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_formatTime(startedAt)} - ${endedAt != null ? _formatTime(endedAt) : 'Ongoing'}',
                  style: TextStyle(
                    fontSize: 14,
                    color: DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Breaks info
            if (breaks.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.coffee,
                    size: 16,
                    color: DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${breaks.length} breaks (${_calculateTotalBreakMinutes(breaks)} min)',
                    style: TextStyle(
                      fontSize: 14,
                      color: DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),

            // Tasks info
            if (tasks.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'Tasks (${tasks.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...tasks.map((task) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        task['status'] == 'DONE'
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 16,
                        color: task['status'] == 'DONE'
                            ? DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.success,
                              )
                            : DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.onSurfaceVariant,
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task['title'],
                              style: TextStyle(
                                fontSize: 14,
                                color: DesignSystem.getSemanticColor(
                                  context,
                                  SemanticColor.onSurface,
                                ),
                              ),
                            ),
                            if (task['category'] != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                task['category'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: DesignSystem.getSemanticColor(
                                    context,
                                    SemanticColor.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (task['actual_minutes'] != null)
                        Text(
                          '${task['actual_minutes']} min',
                          style: TextStyle(
                            fontSize: 12,
                            color: DesignSystem.getSemanticColor(
                              context,
                              SemanticColor.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

// Content widget for use within AppShell.
// Reuses the full ShiftLogsScreen implementation (Recent Shifts + Shift History
// with date/search/status/task filters and time-period grouping) instead of
// maintaining a duplicated simplified copy.
class ShiftLogsScreenContent extends StatelessWidget {
  const ShiftLogsScreenContent({super.key});

  @override
  Widget build(BuildContext context) => const ShiftLogsScreen();
}
