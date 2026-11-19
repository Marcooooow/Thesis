import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/dashboard/services/work_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TaskHistoryScreen extends StatefulWidget {
  const TaskHistoryScreen({super.key});

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  final WorkService _workService = WorkService();

  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _filteredTasks = [];
  List<Map<String, dynamic>> _teamTasks = [];
  String _userRole = 'EMPLOYEE';
  bool get _isManager => _userRole == 'MANAGER' || _userRole == 'ADMIN';
  bool _isLoading = true;
  String? _errorMessage;
     List<dynamic> _lastTasks = [];

  // Filter state
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _categoryFilter = 'All';
  String _statusFilter = 'All';
  String _priorityFilter = 'All';
  String _searchQuery = '';
  String _sortBy = 'Recently Worked';
  final bool _sortAscending = false;

  // Date range presets
  String _dateRangePreset = 'All Time';

  // Available filter options
  final List<String> _categoryFilters = [
    'All',
    'Content Creation',
    'Development',
    'Design',
    'Meeting',
    'Research',
    'Documentation',
  ];

  final List<String> _statusFilters = [
    'All',
    'TODO',
    'IN_PROGRESS',
    'DONE',
    'BLOCKED',
  ];

  final List<String> _priorityFilters = [
    'All',
    'LOW',
    'MEDIUM',
    'HIGH',
  ];

  final List<String> _sortOptions = [
    'Recently Worked',
    'Recently Created',
    'Priority',
    'Due Date',
    'Title',
  ];

  @override
  void initState() {
    super.initState();
    _loadTaskHistory();
  }

   Future<void> _loadTaskHistory() async {
     setState(() {
       _isLoading = true;
       _errorMessage = null;
     });

     try {
       final prefs = await SharedPreferences.getInstance();
       final token = prefs.getString("jwt_token");
       _userRole = prefs.getString("user_role") ?? prefs.getString("role") ?? 'EMPLOYEE';

       if (token == null) {
         // No token -> show empty state (guest users should be routed to DemoShell via AuthGate)
         if (!mounted) return;
         setState(() {
           _tasks = [];
           _isLoading = false;
         });
         return;
       }

       // Authenticated mode - load from backend
       final response = await _workService.getTasksHistory(token);
       List<Map<String, dynamic>> teamTasksRes = [];
       if (_isManager) {
         try {
           final tRes = await _workService.getManagerTeamTasks(token);
           teamTasksRes = List<Map<String, dynamic>>.from(tRes);
         } catch (_) {}
       }

       if (!mounted) return;
       setState(() {
         if (response.isNotEmpty) {
           _tasks = List<Map<String, dynamic>>.from(response);
           _lastTasks = _tasks; // cache the non-empty response
         } else if (_lastTasks.isNotEmpty) {
           _tasks = List<Map<String, dynamic>>.from(_lastTasks);
         } else {
           _tasks = [];
         }
         _teamTasks = teamTasksRes;
         _applyFilters();
         _isLoading = false;
       });
     } catch (e) {
       if (!mounted) return;
       setState(() {
         _errorMessage = "Failed to load task history: $e";
         _isLoading = false;
       });
     }
   }
  void _applyFilters() {
    if (!mounted) return;

    List<Map<String, dynamic>> filtered = List.from(_tasks);

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
          endDate = DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            23,
            59,
            59,
          );
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
        filtered = filtered.where((task) {
          final taskDateStr = task['ended_at'] ?? task['started_at'];
          if (taskDateStr == null) return false;
          final taskDate = DateTime.parse(taskDateStr);
          return taskDate.isAfter(
                startDate!.subtract(const Duration(milliseconds: 1)),
              ) &&
              taskDate.isBefore(endDate!.add(const Duration(days: 1)));
        }).toList();
      } else if (_dateRangePreset == 'Custom') {
        // Handle custom range
        if (_dateFrom != null) {
          filtered = filtered.where((task) {
            final taskDateStr = task['ended_at'] ?? task['started_at'];
            if (taskDateStr == null) return false;
            final taskDate = DateTime.parse(taskDateStr);
            return taskDate.isAtSameMomentAs(_dateFrom!) ||
                taskDate.isAfter(_dateFrom!);
          }).toList();
        }

        if (_dateTo != null) {
          filtered = filtered.where((task) {
            final taskDateStr = task['ended_at'] ?? task['started_at'];
            if (taskDateStr == null) return false;
            final taskDate = DateTime.parse(taskDateStr);
            return taskDate.isAtSameMomentAs(_dateTo!) ||
                taskDate.isBefore(_dateTo!);
          }).toList();
        }
      }
    }

    // Category filter
    if (_categoryFilter != 'All') {
      filtered = filtered.where((task) {
        return task['category'] == _categoryFilter;
      }).toList();
    }

    // Status filter
    if (_statusFilter != 'All') {
      filtered = filtered.where((task) {
        return task['status'] == _statusFilter;
      }).toList();
    }

    // Priority filter
    if (_priorityFilter != 'All') {
      filtered = filtered.where((task) {
        return (task['priority'] ?? 'MEDIUM') == _priorityFilter;
      }).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final queryLower = _searchQuery.toLowerCase();
      filtered = filtered.where((task) {
        final title = (task['title'] ?? '').toLowerCase();
        final category = (task['category'] ?? '').toLowerCase();
        final description = (task['description'] ?? '').toLowerCase();
        return title.contains(queryLower) ||
            category.contains(queryLower) ||
            description.contains(queryLower);
      }).toList();
    }

    // Sorting
    filtered.sort((a, b) {
      int comparison = 0;
      switch (_sortBy) {
        case 'Title':
          final titleA = (a['title'] ?? '').toString().toLowerCase();
          final titleB = (b['title'] ?? '').toString().toLowerCase();
          comparison = titleA.compareTo(titleB);
          break;
        case 'Priority':
          const priorityRank = {'HIGH': 3, 'MEDIUM': 2, 'LOW': 1};
          final pA = priorityRank[a['priority'] ?? 'MEDIUM'] ?? 2;
          final pB = priorityRank[b['priority'] ?? 'MEDIUM'] ?? 2;
          comparison = pB.compareTo(pA);
          break;
        case 'Due Date':
          final dateA = a['deadline'] != null ? DateTime.parse(a['deadline']) : DateTime(2099);
          final dateB = b['deadline'] != null ? DateTime.parse(b['deadline']) : DateTime(2099);
          comparison = dateA.compareTo(dateB);
          break;
        case 'Recently Created':
          final createdA = a['created_at'] != null ? DateTime.parse(a['created_at']) : DateTime(2020);
          final createdB = b['created_at'] != null ? DateTime.parse(b['created_at']) : DateTime(2020);
          comparison = createdB.compareTo(createdA);
          break;
        case 'Recently Worked':
        default:
          final workedA = a['ended_at'] ?? a['started_at'] ?? a['created_at'] ?? '';
          final workedB = b['ended_at'] ?? b['started_at'] ?? b['created_at'] ?? '';
          comparison = workedB.compareTo(workedA);
          break;
      }
      return _sortAscending ? -comparison : comparison;
    });

    setState(() {
      _filteredTasks = filtered;
    });
  }

  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 1100;

    return DefaultTabController(
      length: _isManager ? 3 : 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Container(
            color: Colors.transparent,
            child: TabBar(
              labelColor: DesignSystem.getSemanticColor(context, SemanticColor.primary),
              unselectedLabelColor: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
              indicatorColor: DesignSystem.getSemanticColor(context, SemanticColor.primary),
              tabs: [
                const Tab(text: 'Assigned to Me'),
                const Tab(text: 'My Tasks'),
                if (_isManager) const Tab(text: 'Team Assignments'),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildAssignedToMeTab(context, isDark, isDesktop),
            _buildBody(context, isDark, isDesktop),
            if (_isManager) _buildTeamAssignmentsTab(context, isDark, isDesktop),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignedToMeTab(BuildContext context, bool isDark, bool isDesktop) {
    final assignedTasks = _tasks.where((t) => t['task_type'] == 'WORK' || t['assigned_by_user_id'] != null).toList();
    if (assignedTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_ind_outlined, size: 64, color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('No Manager-assigned tasks yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: assignedTasks.length,
      itemBuilder: (context, index) {
        final task = assignedTasks[index];
        final title = task['title'] ?? 'Untitled Task';
        final status = task['status'] ?? 'TODO';
        final priority = task['priority'] ?? 'MEDIUM';
        final deadline = task['deadline'];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                    Chip(label: Text(status), backgroundColor: status == 'DONE' ? Colors.green.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.2)),
                  ],
                ),
                const SizedBox(height: 8),
                if (task['description'] != null) Text(task['description'], style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Priority: $priority', style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(width: 16),
                    if (deadline != null) Text('Deadline: ${deadline.toString().substring(0, 10)}', style: const TextStyle(color: Colors.orange)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTeamAssignmentsTab(BuildContext context, bool isDark, bool isDesktop) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Team Assignments', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create Work Task modal opened')));
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Work Task'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_teamTasks.isEmpty)
          const Center(child: Text('No team work tasks assigned yet.'))
        else
          ..._teamTasks.map((t) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(t['title'] ?? ''),
                  subtitle: Text('Status: ${t['status']} | Priority: ${t['priority']}'),
                ),
              )),
      ],
    );
  }

  Widget _buildBody(BuildContext context, bool isDark, bool isDesktop) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(
            DesignSystem.getSemanticColor(context, SemanticColor.primary),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTaskHistory,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.task_alt_outlined,
              size: 64,
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurfaceVariant,
              ).withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No task history yet',
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
              'Your completed tasks will appear here',
              style: TextStyle(
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

    return RefreshIndicator(
      onRefresh: _loadTaskHistory,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Task History',
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
            _buildSummaryMetrics(context, isDark),
            const SizedBox(height: 16),
            _buildHistoryFilters(context, isDark, isDesktop),
            const SizedBox(height: 24),
            _buildHistoryContent(context, isDark, isDesktop),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetrics(BuildContext context, bool isDark) {
    final totalCount = _tasks.length;
    final completedCount = _tasks.where((t) => t['status'] == 'DONE').length;
    final inProgressCount = _tasks.where((t) => t['status'] == 'IN_PROGRESS').length;
    final pendingCount = _tasks.where((t) => t['status'] == 'TODO').length;
    final blockedCount = _tasks.where((t) => t['status'] == 'BLOCKED').length;

    final totalMinutes = _tasks.fold<int>(0, (sum, t) => sum + ((t['actual_minutes'] as num?)?.toInt() ?? 0));
    final totalHours = (totalMinutes / 60).toStringAsFixed(1);

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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetricItem(context, 'Total', '$totalCount', Icons.list_alt, SemanticColor.primary),
          _buildMetricItem(context, 'Done', '$completedCount', Icons.check_circle, SemanticColor.success),
          _buildMetricItem(context, 'In Progress', '$inProgressCount', Icons.play_circle_outline, SemanticColor.primary),
          _buildMetricItem(context, 'Pending', '$pendingCount', Icons.schedule, SemanticColor.onSurfaceVariant),
          _buildMetricItem(context, 'Blocked', '$blockedCount', Icons.block, SemanticColor.error),
          _buildMetricItem(context, 'Total Time', '${totalHours}h', Icons.timer, SemanticColor.primary),
        ],
      ),
    );
  }

  Widget _buildMetricItem(BuildContext context, String label, String value, IconData icon, SemanticColor color) {
    final semanticColor = DesignSystem.getSemanticColor(context, color);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: semanticColor),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryFilters(
    BuildContext context,
    bool isDark,
    bool isDesktop,
  ) {
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

    final category = _buildFilterDropdown(
      context,
      'Category',
      _categoryFilter,
      _categoryFilters,
      (value) {
        setState(() {
          _categoryFilter = value!;
          _applyFilters();
        });
      },
      isDark,
    );

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

    final priority = _buildFilterDropdown(
      context,
      'Priority',
      _priorityFilter,
      _priorityFilters,
      (value) {
        setState(() {
          _priorityFilter = value!;
          _applyFilters();
        });
      },
      isDark,
    );

    final sortBy = _buildFilterDropdown(
      context,
      'Sort By',
      _sortBy,
      _sortOptions,
      (value) {
        setState(() {
          _sortBy = value!;
          _applyFilters();
        });
      },
      isDark,
    );

    final applyButton = _buildApplyButton(context);
    final clearButton = _buildClearButton(context);

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 180, child: dateRange),
                const SizedBox(width: 16),
                Flexible(
                  fit: FlexFit.loose,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: search,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(width: 180, child: category),
                const SizedBox(width: 16),
                SizedBox(width: 140, child: status),
                const SizedBox(width: 16),
                SizedBox(width: 140, child: priority),
                const SizedBox(width: 16),
                SizedBox(width: 160, child: sortBy),
                const SizedBox(width: 16),
                _buildToolbarButton(applyButton),
                const SizedBox(width: 12),
                _buildToolbarButton(clearButton),
              ],
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(child: dateRange),
                    const SizedBox(width: 12),
                    Expanded(child: category),
                  ],
                ),
                const SizedBox(height: 12),
                search,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: status),
                    const SizedBox(width: 12),
                    Expanded(child: applyButton),
                  ],
                ),
                const SizedBox(height: 12),
                clearButton,
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
              hintText: 'Search tasks...',
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
      _categoryFilter = 'All';
      _statusFilter = 'All';
      _searchQuery = '';
      _applyFilters();
    });
  }

  Widget _buildHistoryContent(
    BuildContext context,
    bool isDark,
    bool isDesktop,
  ) {
    if (_filteredTasks.isEmpty) {
      return _buildEmptyState(context);
    }

    final groupedTasks = _groupTasksByPeriod(_filteredTasks);

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
        children: groupedTasks.entries.map((entry) {
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
                (task) => _buildTaskRow(context, isDark, task),
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
              Icons.task_alt_outlined,
              size: 48,
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.onSurfaceVariant,
              ).withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks found',
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

  Map<String, List<Map<String, dynamic>>> _groupTasksByPeriod(
    List<Map<String, dynamic>> tasks,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastWeek = today.subtract(const Duration(days: 7));
    final lastMonth = today.subtract(const Duration(days: 30));

    final groups = <String, List<Map<String, dynamic>>>{
      'Today': [],
      'Yesterday': [],
      'Last 7 Days': [],
      'Last 30 Days': [],
      'Older': [],
    };

    for (final task in tasks) {
      final taskDateStr = task['ended_at'] ?? task['started_at'];
      if (taskDateStr == null) continue;

      final taskDate = DateTime.parse(taskDateStr);
      final taskDateOnly = DateTime(
        taskDate.year,
        taskDate.month,
        taskDate.day,
      );

      if (taskDateOnly.isAtSameMomentAs(today)) {
        groups['Today']!.add(task);
      } else if (taskDateOnly.isAtSameMomentAs(yesterday)) {
        groups['Yesterday']!.add(task);
      } else if (taskDateOnly.isAfter(lastWeek) &&
          taskDateOnly.isBefore(yesterday)) {
        groups['Last 7 Days']!.add(task);
      } else if (taskDateOnly.isAfter(lastMonth) &&
          taskDateOnly.isBefore(lastWeek)) {
        groups['Last 30 Days']!.add(task);
      } else {
        groups['Older']!.add(task);
      }
    }

    // Remove empty groups
    groups.removeWhere((key, value) => value.isEmpty);

    return groups;
  }

  Widget _buildTaskRow(
    BuildContext context,
    bool isDark,
    Map<String, dynamic> task,
  ) {
    final startedAt = task['started_at'] != null
        ? DateTime.parse(task['started_at'])
        : null;
    final endedAt = task['ended_at'] != null
        ? DateTime.parse(task['ended_at'])
        : null;
    final actualMinutes = task['actual_minutes'] ?? 0;
    final status = task['status'] ?? 'TODO';
    final priority = task['priority'] ?? 'MEDIUM';
    final deadlineStr = task['deadline'];
    final deadline = deadlineStr != null ? DateTime.parse(deadlineStr) : null;
    final now = DateTime.now();
    final isOverdue = deadline != null && deadline.isBefore(now) && status != 'DONE';
    final isDueToday = deadline != null &&
        deadline.year == now.year &&
        deadline.month == now.month &&
        deadline.day == now.day &&
        status != 'DONE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
          // Status icon
          _buildStatusIcon(context, status),
          const SizedBox(width: 16),
          // Task details
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task['title'] ?? 'Untitled Task',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DesignSystem.getSemanticColor(
                            context,
                            SemanticColor.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildPriorityBadge(context, priority),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      task['category'] ?? 'General',
                      style: TextStyle(
                        fontSize: 12,
                        color: DesignSystem.getSemanticColor(
                          context,
                          SemanticColor.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (deadline != null) ...[
                      const SizedBox(width: 8),
                      _buildDeadlineBadge(context, deadline, isOverdue, isDueToday),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Start time
          Expanded(
            flex: 1,
            child: Text(
              startedAt != null ? _formatTime(startedAt) : '-',
              style: TextStyle(
                fontSize: 13,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurface,
                ),
              ),
            ),
          ),
          // End time
          Expanded(
            flex: 1,
            child: Text(
              endedAt != null ? _formatTime(endedAt) : '-',
              style: TextStyle(
                fontSize: 13,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurface,
                ),
              ),
            ),
          ),
          // Duration
          Expanded(
            flex: 1,
            child: Text(
              _formatDuration(actualMinutes),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.onSurface,
                ),
              ),
            ),
          ),
          // Status label
          _buildStatusBadge(context, status),
        ],
      ),
    );
  }

  Widget _buildPriorityBadge(BuildContext context, String priority) {
    Color color;
    switch (priority) {
      case 'HIGH':
        color = DesignSystem.getSemanticColor(context, SemanticColor.error);
        break;
      case 'LOW':
        color = DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant);
        break;
      case 'MEDIUM':
      default:
        color = DesignSystem.getSemanticColor(context, SemanticColor.primary);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        priority,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildDeadlineBadge(BuildContext context, DateTime? deadline, bool isOverdue, bool isDueToday) {
    if (deadline == null) return const SizedBox.shrink();
    Color color;
    String text;
    if (isOverdue) {
      color = DesignSystem.getSemanticColor(context, SemanticColor.error);
      text = 'Overdue: ${_formatDate(deadline)}';
    } else if (isDueToday) {
      color = DesignSystem.getSemanticColor(context, SemanticColor.primary);
      text = 'Due Today';
    } else {
      color = DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant);
      text = 'Due: ${_formatDate(deadline)}';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  Widget _buildStatusIcon(BuildContext context, String status) {
    IconData icon;
    Color color;

    switch (status) {
      case 'DONE':
        icon = Icons.check_circle;
        color = DesignSystem.getSemanticColor(context, SemanticColor.success);
        break;
      case 'IN_PROGRESS':
        icon = Icons.play_circle_outline;
        color = DesignSystem.getSemanticColor(context, SemanticColor.primary);
        break;
      case 'BLOCKED':
        icon = Icons.block;
        color = DesignSystem.getSemanticColor(context, SemanticColor.error);
        break;
      case 'TODO':
      default:
        icon = Icons.circle_outlined;
        color = DesignSystem.getSemanticColor(
          context,
          SemanticColor.onSurfaceVariant,
        );
    }

    return Icon(icon, size: 20, color: color);
  }

  Widget _buildStatusBadge(BuildContext context, String status) {
    String label;
    Color backgroundColor;
    Color textColor;

    switch (status) {
      case 'DONE':
        label = 'Done';
        backgroundColor = DesignSystem.getSemanticColor(
          context,
          SemanticColor.success,
        ).withValues(alpha: 0.1);
        textColor = DesignSystem.getSemanticColor(
          context,
          SemanticColor.success,
        );
        break;
      case 'IN_PROGRESS':
        label = 'In Progress';
        backgroundColor = DesignSystem.getSemanticColor(
          context,
          SemanticColor.primary,
        ).withValues(alpha: 0.1);
        textColor = DesignSystem.getSemanticColor(
          context,
          SemanticColor.primary,
        );
        break;
      case 'BLOCKED':
        label = 'Blocked';
        backgroundColor = DesignSystem.getSemanticColor(
          context,
          SemanticColor.error,
        ).withValues(alpha: 0.1);
        textColor = DesignSystem.getSemanticColor(context, SemanticColor.error);
        break;
      case 'TODO':
      default:
        label = 'To Do';
        backgroundColor = DesignSystem.getSemanticColor(
          context,
          SemanticColor.onSurfaceVariant,
        ).withValues(alpha: 0.1);
        textColor = DesignSystem.getSemanticColor(
          context,
          SemanticColor.onSurfaceVariant,
        );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
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
}

// Content widget for use within AppShell
class TaskHistoryScreenContent extends StatelessWidget {
  const TaskHistoryScreenContent({super.key});

  @override
  Widget build(BuildContext context) => const TaskHistoryScreen();
}
