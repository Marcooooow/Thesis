import 'package:flutter/material.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/dashboard/services/work_service.dart';
import 'package:intellibreak/features/team/team_service.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/core/motion.dart';
import 'package:intellibreak/providers/work_session_provider.dart';
import 'package:intellibreak/providers/work_session_models.dart';
import 'package:intellibreak/widgets/state_display.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Task-category choices with an "Other" option always available last.
List<String> _categoriesWithOther(Iterable<String> names) {
  final list = names.where((n) => n.trim().toLowerCase() != 'other').toList();
  list.add('Other');
  return list;
}

import 'dart:async';

class WorkTasks extends StatefulWidget {
  const WorkTasks({super.key});

  @override
  State<WorkTasks> createState() => _WorkTasksState();
}

/// Task groupings for chronological display in the timesheet
enum TaskPeriod {
  today,
  yesterday,
  last7Days,
  last30Days,
  older;

  String get label {
    switch (this) {
      case TaskPeriod.today:
        return 'Today';
      case TaskPeriod.yesterday:
        return 'Yesterday';
      case TaskPeriod.last7Days:
        return 'Last 7 Days';
      case TaskPeriod.last30Days:
        return 'Last 30 Days';
      case TaskPeriod.older:
        return 'Older';
    }
  }
}

class _WorkTasksState extends State<WorkTasks> {
  final WorkService _workService = WorkService();
  final TextEditingController _taskTitleController = TextEditingController();
  final TextEditingController _otherCategoryController = TextEditingController();
  bool _isCreating = false;
  String? _selectedCategory = 'Content Creation';

  // Role and tasks
  String _userRole = 'EMPLOYEE';
  bool get _isManager => _userRole == 'MANAGER' || _userRole == 'ADMIN';
  List<Map<String, dynamic>> _assignedWorkTasks = [];
  List<Map<String, dynamic>> _teamAssignments = [];
  Map<String, Map<String, dynamic>> _employeeMap = {};

  // Manual/Timer mode
  bool _isTimerMode = false;
  Timer? _timer;

  // Manual mode controls
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // Filtering
  String _searchQuery = '';
  String? _selectedFilterCategory;
  String? _selectedFilterStatus;
  String _dateRangeFilter = 'All Time';

// Sorting
  String _sortBy = 'Recently Worked'; // Recently Worked, Recently Created, Longest Time, Alphabetical
  bool _sortAscending = false;
  bool _forceShowContent = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _loadRoleAndAssignedTasks();
  }

  Future<void> _loadRoleAndAssignedTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    String role = 'EMPLOYEE';

    if (token != null) {
      try {
        final apiService = ApiService();
        final userData = await apiService.getMe(token);
        role = (userData['role'] ?? 'EMPLOYEE').toString().toUpperCase();
        await prefs.setString('user_role', role);
      } catch (_) {
        role = prefs.getString('user_role') ?? prefs.getString('role') ?? prefs.getString('auth_role') ?? 'EMPLOYEE';
        role = role.toUpperCase();
      }
    } else {
      role = prefs.getString('user_role') ?? prefs.getString('role') ?? 'EMPLOYEE';
      role = role.toUpperCase();
    }

    if (!mounted) return;
    setState(() {
      _userRole = role;
    });

    if (token != null) {
      try {
        final history = await _workService.getTasksHistory(token);
        if (mounted) {
          setState(() {
            _assignedWorkTasks = List<Map<String, dynamic>>.from(
              history.where((t) => t['task_type'] == 'WORK' || t['assigned_by_user_id'] != null)
            );
          });
        }
        if (_isManager) {
          try {
            final results = await Future.wait([
              _workService.getManagerTeamTasks(token),
              TeamService().getMyTeamView(token),
            ]);
            final teamTasks = results[0];
            final teamMembers = results[1];
            final empMap = <String, Map<String, dynamic>>{};
            for (final m in teamMembers) {
              final pId = m['profile_id']?.toString() ?? m['id']?.toString();
              if (pId != null) {
                empMap[pId] = Map<String, dynamic>.from(m);
              }
            }
            if (mounted) {
              setState(() {
                _teamAssignments = List<Map<String, dynamic>>.from(teamTasks);
                _employeeMap = empMap;
              });
            }
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  String? get _effectiveCategory {
    if (_selectedCategory == 'Other') {
      final value = _otherCategoryController.text.trim();
      return value.isEmpty ? null : value;
    }
    return _selectedCategory;
  }

  Widget _otherCategoryField() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: _otherCategoryController,
          decoration: const InputDecoration(
            labelText: 'Other category',
            hintText: 'Type your own category',
            isDense: true,
          ),
        ),
      );

  @override
  void dispose() {
    _timer?.cancel();
    _taskTitleController.dispose();
    _otherCategoryController.dispose();
    super.dispose();
  }

  

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final sessionProvider = Provider.of<WorkSessionProvider>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = themeController.isHighContrast;
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;

    final personalTaskWidget = StateDisplay(
      isLoading: sessionProvider.isLoading,
      errorMessage: sessionProvider.lastError,
      isEmpty: !sessionProvider.isLoading &&
          sessionProvider.lastError == null &&
          (sessionProvider.state.tasks.isEmpty && !_forceShowContent),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Compact task entry toolbar
          _buildTaskEntryBar(context, isDark, isHighContrast, isDesktop),
          const SizedBox(height: 24),
          // Filters (compact)
          _buildFilters(context, isDark, isHighContrast, isDesktop),
          const SizedBox(height: 24),
          // Timesheet
          _buildTimesheet(context, isDark, isHighContrast, isDesktop),
        ],
      ),
      onRetry: () => sessionProvider.refresh(),
      loadingMessage: 'Loading your tasks...',
      emptyMessage: sessionProvider.state.tasks.isEmpty
          ? 'No tasks yet'
          : 'No matching tasks',
      emptyAction: ElevatedButton.icon(
        onPressed: () {
          setState(() => _forceShowContent = true);
        },
        icon: const Icon(Icons.add),
        label: const Text('Create a task'),
      ),
    );

    return DefaultTabController(
      length: _isManager ? 3 : 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                  width: 1,
                ),
              ),
            ),
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
          const SizedBox(height: 16),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: TabBarView(
              children: [
                _buildAssignedToMeTab(context),
                personalTaskWidget,
                if (_isManager) _buildTeamAssignmentsTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedToMeTab(BuildContext context) {
    if (_assignedWorkTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_ind_outlined, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('No Manager-assigned tasks yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _assignedWorkTasks.length,
      itemBuilder: (context, index) {
        final task = _assignedWorkTasks[index];
        final title = task['title'] ?? 'Untitled';
        final status = task['status'] ?? 'TODO';
        final priority = task['priority'] ?? 'MEDIUM';
        final deadline = task['deadline'];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
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

  Widget _buildTeamAssignmentsTab(BuildContext context) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final task in _teamAssignments) {
      final key = '${task['title'] ?? 'Untitled'} | ${task['category'] ?? 'General'} | ${task['deadline'] ?? ''}';
      grouped.putIfAbsent(key, () => []).add(task);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Team Assignments', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: () => _showCreateWorkTaskDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Work Task'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_teamAssignments.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text('No team work tasks assigned yet.'),
            ),
          )
        else
          ...grouped.entries.map((entry) {
            final tasks = entry.value;
            final sample = tasks.first;
            final title = sample['title'] ?? 'Untitled';
            final category = sample['category'] ?? 'General';
            final priority = sample['priority'] ?? 'MEDIUM';
            final deadline = sample['deadline'];

            final total = tasks.length;
            final completed = tasks.where((t) => t['status'] == 'DONE').length;
            final progress = total > 0 ? (completed / total) : 0.0;
            final percentage = (progress * 100).round();

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text(category, style: const TextStyle(fontSize: 11)),
                          backgroundColor: Colors.blue.withValues(alpha: 0.1),
                          padding: EdgeInsets.zero,
                        ),
                        const SizedBox(width: 4),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20),
                          onSelected: (val) {
                            if (val == 'edit') {
                              _showEditTaskGroupDialog(context, sample, tasks);
                            } else if (val == 'assignees') {
                              _showManageAssigneesDialog(context, sample, tasks);
                            } else if (val == 'details') {
                              _showAssignmentDetailsDialog(context, sample, tasks);
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(value: 'edit', child: Text('Edit Task')),
                            const PopupMenuItem(value: 'assignees', child: Text('Manage Assignees')),
                            const PopupMenuItem(value: 'details', child: Text('View Assignment Details')),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('Priority: $priority', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 12),
                        if (deadline != null)
                          Text('Deadline: ${deadline.toString().substring(0, 10)}', style: const TextStyle(fontSize: 12, color: Colors.orange)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$total assigned employees', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text('$completed of $total completed ($percentage%)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          percentage == 100 ? Colors.green : Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
                children: [
                  const Divider(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Assigned Employees & Progress', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  ...tasks.map((t) {
                    final pId = t['profile_id']?.toString();
                    final emp = pId != null ? _employeeMap[pId] : null;
                    final empName = emp?['full_name'] ?? emp?['name'] ?? emp?['email'] ?? 'Employee';
                    final empEmail = emp?['email']?.toString() ?? '';
                    final status = t['status'] ?? 'TODO';
                    final initials = empName.isNotEmpty
                        ? empName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
                        : 'E';

                    Color statusColor = Colors.blue;
                    if (status == 'DONE') statusColor = Colors.green;
                    if (status == 'IN_PROGRESS') statusColor = Colors.orange;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.blue.withValues(alpha: 0.2),
                            child: Text(initials, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(empName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                if (empEmail.isNotEmpty)
                                  Text(empEmail, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                          Chip(
                            label: Text(status, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)),
                            backgroundColor: statusColor.withValues(alpha: 0.1),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
      ],
    );
  }

  Future<void> _showCreateWorkTaskDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;

    List<dynamic> teamMembers = [];
    List<dynamic> categories = [];
    String? teamMembersError;

    final teamService = TeamService();
    try {
      teamMembers = await teamService.getMyTeamView(token);
    } catch (e) {
      debugPrint('[WORK_TASKS] Failed to load team members: $e');
      teamMembersError = e.toString();
    }

    try {
      categories = await _workService.getTaskCategories(token);
    } catch (e) {
      debugPrint('[WORK_TASKS] Failed to load task categories: $e');
    }

    if (!mounted) return;

    Set<String> selectedProfileIds = {};
    String searchQuery = '';
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final categoryOtherController = TextEditingController();
    final categoryList = categories.isNotEmpty
        ? categories.map((c) => c['name'].toString()).toList()
        : ['General', 'Development', 'Review', 'Planning', 'Meeting', 'Support'];
    String? selectedCategory = categoryList.isNotEmpty ? categoryList[0] : 'General';
    String priority = 'MEDIUM';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final filteredMembers = teamMembers.where((m) {
              final name = (m['full_name'] ?? m['name'] ?? m['email'] ?? '').toString().toLowerCase();
              return name.contains(searchQuery.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text('Create & Assign Work Task'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select Employees *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      if (teamMembersError != null)
                        Text('Error loading team members: $teamMembersError', style: const TextStyle(color: Colors.red, fontSize: 12))
                      else if (teamMembers.isEmpty)
                        const Text('No team members found. Ensure you manage a team.', style: TextStyle(color: Colors.red))
                      else ...[
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Search employees...',
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                          onChanged: (val) {
                            setStateDialog(() => searchQuery = val);
                          },
                        ),
                        const SizedBox(height: 8),
                        if (selectedProfileIds.isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: selectedProfileIds.map((pId) {
                              final member = teamMembers.firstWhere(
                                (m) => (m['profile_id']?.toString() ?? m['id']?.toString()) == pId,
                                orElse: () => {'full_name': 'Employee'},
                              );
                              final name = member['full_name'] ?? member['name'] ?? member['email'] ?? 'Employee';
                              return Chip(
                                label: Text(name),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () {
                                  setStateDialog(() {
                                    selectedProfileIds.remove(pId);
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Container(
                          height: 140,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: filteredMembers.isEmpty
                              ? const Center(child: Text('No matching employees'))
                              : ListView.builder(
                                  itemCount: filteredMembers.length,
                                  itemBuilder: (context, index) {
                                    final member = filteredMembers[index];
                                    final pId = member['profile_id']?.toString() ?? member['id']?.toString() ?? '';
                                    final name = member['full_name'] ?? member['name'] ?? member['email'] ?? 'Employee';
                                    final email = member['email']?.toString() ?? '';
                                    final isSelected = selectedProfileIds.contains(pId);

                                    return CheckboxListTile(
                                      title: Text(name),
                                      subtitle: email.isNotEmpty ? Text(email, style: const TextStyle(fontSize: 12)) : null,
                                      value: isSelected,
                                      dense: true,
                                      onChanged: (bool? checked) {
                                        setStateDialog(() {
                                          if (checked == true) {
                                            selectedProfileIds.add(pId);
                                          } else {
                                            selectedProfileIds.remove(pId);
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Task Title *'),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(labelText: 'Description (Optional)'),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'Category'),
                        value: selectedCategory,
                        items: _categoriesWithOther(categories.isNotEmpty
                                ? categories.map((c) => c['name'].toString())
                                : ['General', 'Development', 'Review', 'Planning', 'Meeting', 'Support'])
                            .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setStateDialog(() {
                              selectedCategory = val;
                              if (val != 'Other') categoryOtherController.clear();
                            });
                          }
                        },
                      ),
                      if (selectedCategory == 'Other') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: categoryOtherController,
                          onChanged: (_) => setStateDialog(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Other category',
                            hintText: 'Type your own category',
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'Priority'),
                        value: priority,
                        items: ['LOW', 'MEDIUM', 'HIGH', 'URGENT'].map((p) {
                          return DropdownMenuItem(value: p, child: Text(p));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setStateDialog(() => priority = val);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedProfileIds.isEmpty ||
                          titleController.text.trim().isEmpty ||
                          (selectedCategory == 'Other' && categoryOtherController.text.trim().isEmpty)
                      ? null
                      : () async {
                          int successCount = 0;
                          int failCount = 0;
                          for (final pId in selectedProfileIds) {
                            try {
                              final data = <String, dynamic>{
                                'profile_id': pId,
                                'title': titleController.text.trim(),
                                'priority': priority,
                              };
                              if (descriptionController.text.trim().isNotEmpty) {
                                data['description'] = descriptionController.text.trim();
                              }
                              if (selectedCategory != null && selectedCategory!.isNotEmpty) {
                                data['category'] = selectedCategory == 'Other'
                                    ? categoryOtherController.text.trim()
                                    : selectedCategory;
                              }
                              await _workService.assignManagerTask(token, data);
                              successCount++;
                            } catch (_) {
                              failCount++;
                            }
                          }
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  failCount == 0
                                      ? 'Successfully assigned task to $successCount employee(s)'
                                      : 'Assigned to $successCount, failed for $failCount employee(s)',
                                ),
                              ),
                            );
                            _loadRoleAndAssignedTasks();
                          }
                        },
                  child: Text('Assign Task (${selectedProfileIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditTaskGroupDialog(
    BuildContext context,
    Map<String, dynamic> sample,
    List<dynamic> tasks,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;

    final titleController = TextEditingController(text: sample['title'] ?? '');
    final descriptionController = TextEditingController(text: sample['description'] ?? '');
    final estMinutesController = TextEditingController(text: sample['estimated_minutes']?.toString() ?? '');
    final categoryOtherController = TextEditingController();
    String priority = sample['priority'] ?? 'MEDIUM';
    String category = sample['category'] ?? 'General';

    List<dynamic> categories = [];
    try {
      categories = await _workService.getTaskCategories(token);
    } catch (_) {}

    final categoryList = _categoriesWithOther(categories.isNotEmpty
        ? categories.map((c) => c['name'].toString())
        : ['General', 'Development', 'Review', 'Planning', 'Meeting', 'Support']);
    if (!categoryList.contains(category)) categoryList.add(category);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Edit Team Assignment'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Task Title'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(labelText: 'Description (Optional)'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Category'),
                      value: category,
                      items: categoryList.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setStateDialog(() {
                            category = val;
                            if (val != 'Other') categoryOtherController.clear();
                          });
                        }
                      },
                    ),
                    if (category == 'Other') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: categoryOtherController,
                        onChanged: (_) => setStateDialog(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Other category',
                          hintText: 'Type your own category',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Priority'),
                      value: priority,
                      items: ['LOW', 'MEDIUM', 'HIGH', 'URGENT']
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setStateDialog(() => priority = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: estMinutesController,
                      decoration: const InputDecoration(labelText: 'Estimated Minutes'),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: category == 'Other' && categoryOtherController.text.trim().isEmpty
                      ? null
                      : () async {
                    final newTitle = titleController.text.trim();
                    if (newTitle.isEmpty) return;

                    final updateData = <String, dynamic>{
                      'title': newTitle,
                      'description': descriptionController.text.trim(),
                      'category': category == 'Other'
                          ? categoryOtherController.text.trim()
                          : category,
                      'priority': priority,
                    };
                    if (estMinutesController.text.isNotEmpty) {
                      updateData['estimated_minutes'] = int.tryParse(estMinutesController.text) ?? 0;
                    }

                    int success = 0;
                    for (final task in tasks) {
                      try {
                        final taskId = task['id']?.toString();
                        if (taskId != null) {
                          await _workService.updateManagerTask(token, taskId, updateData);
                          success++;
                        }
                      } catch (_) {}
                    }

                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Updated task for $success employee(s)')),
                      );
                      _loadRoleAndAssignedTasks();
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showManageAssigneesDialog(
    BuildContext context,
    Map<String, dynamic> sample,
    List<dynamic> tasks,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;

    List<dynamic> teamMembers = [];
    try {
      final teamService = TeamService();
      teamMembers = await teamService.getMyTeamView(token);
    } catch (_) {}

    if (!context.mounted) return;

    String searchQuery = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final assignedProfileIds = tasks.map((t) => t['profile_id']?.toString()).toSet();
            final availableMembers = teamMembers.where((m) {
              final pId = (m['profile_id']?.toString() ?? m['id']?.toString());
              if (assignedProfileIds.contains(pId)) return false;
              if (searchQuery.isEmpty) return true;
              final name = (m['full_name'] ?? m['name'] ?? m['email'] ?? '').toString().toLowerCase();
              return name.contains(searchQuery.toLowerCase());
            }).toList();

            return AlertDialog(
              title: Text('Manage Assignees: ${sample['title']}'),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.6,
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Currently Assigned', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 2,
                      child: ListView.builder(
                        itemCount: tasks.length,
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          final status = task['status'] ?? 'TODO';
                          final pId = task['profile_id']?.toString();
                          final member = teamMembers.firstWhere(
                            (m) => (m['profile_id']?.toString() ?? m['id']?.toString()) == pId,
                            orElse: () => {'full_name': 'Employee'},
                          );
                          final name = member['full_name'] ?? member['name'] ?? member['email'] ?? 'Employee';

                          return ListTile(
                            title: Text(name),
                            subtitle: Text('Status: $status | Actual Mins: ${task['actual_minutes'] ?? 0}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Confirm Removal'),
                                    content: Text('Remove $name from this task assignment? Historical records will be preserved.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () => Navigator.of(c).pop(true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  try {
                                    await _workService.removeManagerTask(token, task['id'].toString());
                                    if (ctx.mounted) {
                                      setStateDialog(() {
                                        tasks.removeAt(index);
                                      });
                                    }
                                    if (mounted) _loadRoleAndAssignedTasks();
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to remove: $e')),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 24),
                    const Text('Add Employees', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search available employees...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (val) => setStateDialog(() => searchQuery = val),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 2,
                      child: ListView.builder(
                        itemCount: availableMembers.length,
                        itemBuilder: (context, index) {
                          final member = availableMembers[index];
                          final pId = (member['profile_id']?.toString() ?? member['id']?.toString());
                          final name = member['full_name'] ?? member['name'] ?? member['email'] ?? 'Employee';

                          return ListTile(
                            title: Text(name),
                            subtitle: Text(member['email'] ?? ''),
                            trailing: ElevatedButton(
                              onPressed: pId == null ? null : () async {
                                try {
                                  final data = <String, dynamic>{
                                    'profile_id': pId,
                                    'title': sample['title'],
                                    'description': sample['description'],
                                    'category': sample['category'],
                                    'priority': sample['priority'] ?? 'MEDIUM',
                                    'estimated_minutes': sample['estimated_minutes'] ?? 60,
                                  };
                                  if (sample['deadline'] != null) {
                                    data['deadline'] = sample['deadline'];
                                  }
                                  final res = await _workService.assignManagerTask(token, data);
                                  if (res['workload_analysis'] != null && res['workload_analysis']['status'] == 'OVERLOADED') {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Warning: Employee workload is high/overloaded.')),
                                      );
                                    }
                                  }
                                  if (ctx.mounted) {
                                    setStateDialog(() {
                                      tasks.add(res);
                                    });
                                  }
                                  if (mounted) _loadRoleAndAssignedTasks();
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Failed to add employee: $e')),
                                    );
                                  }
                                }
                              },
                              child: const Text('Add'),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAssignmentDetailsDialog(
    BuildContext context,
    Map<String, dynamic> sample,
    List<dynamic> tasks,
  ) async {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Assignment Details: ${sample['title']}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Category: ${sample['category'] ?? 'General'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Priority: ${sample['priority'] ?? 'MEDIUM'}'),
                const SizedBox(height: 8),
                Text('Description: ${sample['description'] ?? 'No description'}'),
                const SizedBox(height: 8),
                Text('Deadline: ${sample['deadline'] ?? 'No deadline'}'),
                const SizedBox(height: 16),
                const Text('Assignees Summary:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...tasks.map((t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('• Status: ${t['status']} | Actual Time: ${t['actual_minutes'] ?? 0} mins'),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTaskEntryBar(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    bool isDesktop,
  ) {
    final theme = Theme.of(context);

    if (!isDesktop) {
      // Mobile: stacked layout
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? (isHighContrast
                    ? const Color(0xFF0D0D0D)
                    : const Color(0xFF151A21))
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? (isHighContrast
                      ? Colors.white.withValues(alpha: 0.3)
                      : const Color(0xFF262D37))
                : const Color(0xFFE2E6EB),
          ),
        ),
        child: Column(
          children: [
            TextField(
              controller: _taskTitleController,
              decoration: InputDecoration(
                hintText: 'What are you working on?',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Content Creation',
                        child: Text('Content Creation'),
                      ),
                      DropdownMenuItem(
                        value: 'Development',
                        child: Text('Development'),
                      ),
                      DropdownMenuItem(value: 'Design', child: Text('Design')),
                      DropdownMenuItem(
                        value: 'Meeting',
                        child: Text('Meeting'),
                      ),
                      DropdownMenuItem(
                        value: 'Research',
                        child: Text('Research'),
                      ),
                      DropdownMenuItem(
                        value: 'Documentation',
                        child: Text('Documentation'),
                      ),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (value) => setState(() {
                      _selectedCategory = value;
                      if (value != 'Other') _otherCategoryController.clear();
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                if (!_isTimerMode)
                  IconButton(
                    icon: const Icon(Icons.calendar_today, size: 20),
                    onPressed: _selectDate,
                  ),
              ],
            ),
            if (_selectedCategory == 'Other') _otherCategoryField(),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!_isTimerMode) ...[
                  Expanded(
                    child: InkWell(
                      onTap: _selectStartTime,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _startTime == null
                              ? 'Start'
                              : '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: _selectEndTime,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _endTime == null
                              ? 'End'
                              : '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ] else
                  Expanded(
                    child: Consumer<WorkSessionProvider>(
                      builder: (context, sessionProvider, child) {
                        final elapsed = sessionProvider.state.startTime != null
                            ? DateTime.now().difference(sessionProvider.state.startTime!)
                            : Duration.zero;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.colorScheme.outline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _formatElapsedTime(elapsed.inSeconds),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isCreating
                      ? null
                      : _handleStartPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    _isTimerMode ? 'Start' : 'Add',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Manual'),
                  selected: !_isTimerMode,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _isTimerMode = false;
                        // No local timer to stop - timing handled by providers
                      });
                    }
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Timer'),
                  selected: _isTimerMode,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _isTimerMode = true;
                        _selectedDate = null;
                        _startTime = null;
                        _endTime = null;
                      });
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Desktop: compact horizontal bar
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast
                  ? const Color(0xFF0D0D0D)
                  : const Color(0xFF151A21))
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.3)
                    : const Color(0xFF262D37))
              : const Color(0xFFE2E6EB),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;

          // For very narrow screens, use column layout
          if (screenWidth < 400) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _taskTitleController,
                  decoration: InputDecoration(
                    hintText: 'What are you working on?',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  items: const [DropdownMenuItem(value: 'Content Creation', child: Text('Content Creation')), DropdownMenuItem(value: 'Development', child: Text('Development')), DropdownMenuItem(value: 'Design', child: Text('Design')), DropdownMenuItem(value: 'Other', child: Text('Other'))],
                  onChanged: (v) => setState(() {
                    _selectedCategory = v;
                    if (v != 'Other') _otherCategoryController.clear();
                  }),
                ),
                if (_selectedCategory == 'Other') _otherCategoryField(),
              ],
            );
          }

          // For desktop and wider screens, try row layout first
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
              // Task description - flexible, takes remaining space
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _taskTitleController,
                  decoration: InputDecoration(
                    hintText: 'What are you working on?',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Category - adequate space for dropdown
              Expanded(
                flex: 2,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 120,
                    maxWidth: 180,
                  ),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Content Creation',
                        child: Text('Content Creation'),
                      ),
                      DropdownMenuItem(
                        value: 'Development',
                        child: Text('Development'),
                      ),
                      DropdownMenuItem(value: 'Design', child: Text('Design')),
                      DropdownMenuItem(value: 'Meeting', child: Text('Meeting')),
                      DropdownMenuItem(value: 'Research', child: Text('Research')),
                      DropdownMenuItem(
                        value: 'Documentation',
                        child: Text('Documentation'),
                      ),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (value) => setState(() {
                      _selectedCategory = value;
                      if (value != 'Other') _otherCategoryController.clear();
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Time display/control
              if (!_isTimerMode) ...[
                // Time inputs in a compact row
                SizedBox(
                  width: 180,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: InkWell(
                          onTap: _selectStartTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.colorScheme.outline),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _startTime == null
                                  ? '--:--'
                                  : '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          '-',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: InkWell(
                          onTap: _selectEndTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.colorScheme.outline),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _endTime == null
                                  ? '--:--'
                                  : '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  onPressed: _selectDate,
                  tooltip: 'Select date',
                  constraints: const BoxConstraints(),
                ),
              ] else
                Container(
                  width: 100,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Consumer<WorkSessionProvider>(
                    builder: (context, sessionProvider, child) {
                      final elapsed = sessionProvider.state.startTime != null
                          ? DateTime.now().difference(sessionProvider.state.startTime!)
                          : Duration.zero;
                      return Text(
                        _formatElapsedTime(elapsed.inSeconds),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      );
                    },
                  ),
                ),
              const SizedBox(width: 8),
              // Start/Stop button
              ElevatedButton.icon(
                onPressed: _isCreating
                    ? null
                    : _handleStartPressed,
                icon: Icon(
                  _isTimerMode ? Icons.play_arrow : Icons.add,
                  size: 18,
                ),
                label: Text(
                  _isTimerMode ? 'Start' : 'Add',
                  style: const TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),
              // Mode toggle - compact
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Manual'),
                    icon: Icon(Icons.edit_calendar, size: 14),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Timer'),
                    icon: Icon(Icons.timer, size: 14),
                  ),
                ],
                selected: {_isTimerMode},
                onSelectionChanged: (Set<bool> selected) {
                  setState(() {
                    _isTimerMode = selected.first;
                    if (_isTimerMode) {
                      _selectedDate = null;
                      _startTime = null;
                      _endTime = null;
                    } else {
                      // No local timer to stop - timing handled by providers
                    }
                  });
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
                ],
              ),
              if (_selectedCategory == 'Other') _otherCategoryField(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilters(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    bool isDesktop,
  ) {
    if (!isDesktop) {
      // Mobile: stacked filters
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? (isHighContrast
                    ? const Color(0xFF0D0D0D)
                    : const Color(0xFF151A21))
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? (isHighContrast
                      ? Colors.white.withValues(alpha: 0.3)
                      : const Color(0xFF262D37))
                : const Color(0xFFE2E6EB),
          ),
        ),
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Search tasks...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _sortBy,
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Recently Worked',
                        child: Text('Recently Worked'),
                      ),
                      DropdownMenuItem(
                        value: 'Recently Created',
                        child: Text('Recently Created'),
                      ),
                      DropdownMenuItem(
                        value: 'Longest Time',
                        child: Text('Longest Time'),
                      ),
                      DropdownMenuItem(
                        value: 'Alphabetical',
                        child: Text('Alphabetical'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _sortBy = value!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedFilterCategory,
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('All Categories'),
                      ),
                      DropdownMenuItem(
                        value: 'Content Creation',
                        child: Text('Content Creation'),
                      ),
                      DropdownMenuItem(
                        value: 'Development',
                        child: Text('Development'),
                      ),
                      DropdownMenuItem(value: 'Design', child: Text('Design')),
                      DropdownMenuItem(
                        value: 'Meeting',
                        child: Text('Meeting'),
                      ),
                      DropdownMenuItem(
                        value: 'Research',
                        child: Text('Research'),
                      ),
                      DropdownMenuItem(
                        value: 'Documentation',
                        child: Text('Documentation'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedFilterCategory = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _dateRangeFilter,
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'All Time',
                        child: Text('All Time'),
                      ),
                      DropdownMenuItem(value: 'Today', child: Text('Today')),
                      DropdownMenuItem(
                        value: 'Yesterday',
                        child: Text('Yesterday'),
                      ),
                      DropdownMenuItem(
                        value: 'Last 7 Days',
                        child: Text('Last 7 Days'),
                      ),
                      DropdownMenuItem(
                        value: 'Last 30 Days',
                        child: Text('Last 30 Days'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _dateRangeFilter = value!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedFilterStatus,
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('All Statuses'),
                      ),
                      DropdownMenuItem(value: 'TODO', child: Text('To Do')),
                      DropdownMenuItem(
                        value: 'IN_PROGRESS',
                        child: Text('In Progress')),
                      DropdownMenuItem(value: 'DONE', child: Text('Done')),
                      DropdownMenuItem(
                        value: 'BLOCKED',
                        child: Text('Blocked'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedFilterStatus = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Apply'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _searchQuery = '';
                      _selectedFilterCategory = null;
                      _selectedFilterStatus = null;
                      _dateRangeFilter = 'All Time';
                      _sortBy = 'Recently Worked';
                      _sortAscending = true;
                    }),
                    child: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Desktop: responsive filter bar
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final bool isWideScreen = screenWidth >= 1100; // Match isDesktop breakpoint

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? (isHighContrast
                      ? const Color(0xFF0D0D0D)
                      : const Color(0xFF151A21))
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.3)
                        : const Color(0xFF262D37))
                  : const Color(0xFFE2E6EB),
            ),
          ),
          child: isWideScreen
              ? _buildDesktopFilters(context, isDark, isHighContrast)
              : _buildWrapFilters(context, isDark, isHighContrast),
        );
      },
    );
  }

  Widget _buildDesktopFilters(BuildContext context, bool isDark, bool isHighContrast) {
    return Row(
      children: [
        // Sort dropdown - expanded to fit content
        Expanded(
          flex: 2,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 140, // Ensures enough width for "Recently Created"
              maxWidth: 200,
            ),
            child: DropdownButtonFormField<String>(
              initialValue: _sortBy,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'Recently Worked',
                  child: Text('Recently Worked'),
                ),
                DropdownMenuItem(
                  value: 'Recently Created',
                  child: Text('Recently Created'),
                ),
                DropdownMenuItem(
                  value: 'Longest Time',
                  child: Text('Longest Time'),
                ),
                DropdownMenuItem(
                  value: 'Alphabetical',
                  child: Text('Alphabetical'),
                ),
              ],
              onChanged: (value) => setState(() => _sortBy = value!),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Date range filter
        Expanded(
          flex: 2,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: DropdownButtonFormField<String>(
              initialValue: _dateRangeFilter,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'All Time', child: Text('All Time')),
                DropdownMenuItem(value: 'Today', child: Text('Today')),
                DropdownMenuItem(value: 'Yesterday', child: Text('Yesterday')),
                DropdownMenuItem(
                  value: 'Last 7 Days',
                  child: Text('Last 7 Days'),
                ),
                DropdownMenuItem(
                  value: 'Last 30 Days',
                  child: Text('Last 30 Days'),
                ),
              ],
              onChanged: (value) => setState(() => _dateRangeFilter = value!),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Search field - takes remaining space
        Expanded(
          flex: 3,
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search tasks...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        const SizedBox(width: 12),

        // Category filter
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String?>(
            initialValue: _selectedFilterCategory,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('All Categories')),
              DropdownMenuItem(value: 'Content Creation', child: Text('Content Creation')),
              DropdownMenuItem(value: 'Development', child: Text('Development')),
              DropdownMenuItem(value: 'Design', child: Text('Design')),
              DropdownMenuItem(value: 'Meeting', child: Text('Meeting')),
              DropdownMenuItem(value: 'Research', child: Text('Research')),
              DropdownMenuItem(value: 'Documentation', child: Text('Documentation')),
            ],
            onChanged: (value) => setState(() => _selectedFilterCategory = value),
          ),
        ),
        // Status filter
        Expanded(
          flex: 1,
          child: DropdownButtonFormField<String?>(
            initialValue: _selectedFilterStatus,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('All Statuses')),
              DropdownMenuItem(value: 'TODO', child: Text('To Do')),
              DropdownMenuItem(value: 'IN_PROGRESS', child: Text('In Progress')),
              DropdownMenuItem(value: 'DONE', child: Text('Done')),
              DropdownMenuItem(value: 'BLOCKED', child: Text('Blocked')),
            ],
            onChanged: (value) => setState(() => _selectedFilterStatus = value),
          ),
        ),
        // Apply button
        ElevatedButton(
          onPressed: () => setState(() {}),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text('Apply'),
        ),
        const SizedBox(width: 8),

        // Clear button
        OutlinedButton(
          onPressed: () => setState(() {
            _searchQuery = '';
            _selectedFilterCategory = null;
            _selectedFilterStatus = null;
            _dateRangeFilter = 'All Time';
            _sortBy = 'Recently Worked';
            _sortAscending = true;
          }),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text('Clear'),
        ),
      ],
    );
  }

  Widget _buildWrapFilters(BuildContext context, bool isDark, bool isHighContrast) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: DropdownButtonFormField<String>(
            initialValue: _sortBy,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: 'Recently Worked',
                child: Text('Recently Worked'),
              ),
              DropdownMenuItem(
                value: 'Recently Created',
                child: Text('Recently Created'),
              ),
              DropdownMenuItem(
                value: 'Longest Time',
                child: Text('Longest Time'),
              ),
              DropdownMenuItem(
                value: 'Alphabetical',
                child: Text('Alphabetical'),
              ),
            ],
            onChanged: (value) => setState(() => _sortBy = value!),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: DropdownButtonFormField<String>(
            initialValue: _dateRangeFilter,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'All Time', child: Text('All Time')),
              DropdownMenuItem(value: 'Today', child: Text('Today')),
              DropdownMenuItem(value: 'Yesterday', child: Text('Yesterday')),
              DropdownMenuItem(
                value: 'Last 7 Days',
                child: Text('Last 7 Days'),
              ),
              DropdownMenuItem(
                value: 'Last 30 Days',
                child: Text('Last 30 Days'),
              ),
            ],
            onChanged: (value) => setState(() => _dateRangeFilter = value!),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search tasks...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: DropdownButtonFormField<String?>(
            initialValue: _selectedFilterCategory,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('All Categories')),
              DropdownMenuItem(
                value: 'Content Creation',
                child: Text('Content Creation'),
              ),
              DropdownMenuItem(
                value: 'Development',
                child: Text('Development'),
              ),
              DropdownMenuItem(value: 'Design', child: Text('Design')),
              DropdownMenuItem(value: 'Meeting', child: Text('Meeting')),
              DropdownMenuItem(value: 'Research', child: Text('Research')),
              DropdownMenuItem(
                value: 'Documentation',
                child: Text('Documentation'),
              ),
            ],
            onChanged: (value) =>
                setState(() => _selectedFilterCategory = value),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 100),
          child: DropdownButtonFormField<String?>(
            initialValue: _selectedFilterStatus,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('All Statuses')),
              DropdownMenuItem(value: 'TODO', child: Text('To Do')),
              DropdownMenuItem(
                value: 'IN_PROGRESS',
                child: Text('In Progress'),
              ),
              DropdownMenuItem(value: 'DONE', child: Text('Done')),
              DropdownMenuItem(
                value: 'BLOCKED',
                child: Text('Blocked')
              ),
            ],
            onChanged: (value) =>
                setState(() => _selectedFilterStatus = value),
          ),
        ),
        ElevatedButton(
          onPressed: () => setState(() {}),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text('Apply'),
        ),
        OutlinedButton(
          onPressed: () => setState(() {
            _searchQuery = '';
            _selectedFilterCategory = null;
            _selectedFilterStatus = null;
            _dateRangeFilter = 'All Time';
            _sortBy = 'Recently Worked';
            _sortAscending = true;
          }),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text('Clear'),
        ),
      ],
    );
  }

  Widget _buildTimesheet(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    bool isDesktop,
  ) {
    final filteredTasks = _applyFiltersToTasks();
    final grouped = _groupTasksByPeriod(filteredTasks);

    // Create a key based on the filtered tasks to trigger animations when the list changes
    final tasksKey = ValueKey<String>(
      filteredTasks.map((task) => task.id).toList().join('_'),
    );

    return AnimatedSwitcher(
      duration: MotionDurations.component,
      switchInCurve: MotionCurves.easeOutCubic,
      switchOutCurve: MotionCurves.easeInOut,
      child: Column(
        key: tasksKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Week header
          DelayedAnimatedSection(
            delay: Duration.zero,
            slideDirection: SlideDirection.topToBottom,
            visible: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'This Week',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? (isHighContrast ? Colors.white : const Color(0xFFE8EBEF))
                        : const Color(0xFF111827),
                  ),
                ),
                Text(
                  'Week Total: ${_calculateTotalDuration(filteredTasks)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? (isHighContrast
                            ? Colors.white.withValues(alpha: 0.8)
                            : const Color(0xFF9AA3AF))
                        : const Color(0xFF5B6472),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Task groups
          ...grouped.entries.toList().asMap().entries.map((entryMap) {
            final index = entryMap.key;
            final entry = entryMap.value;
            return DelayedAnimatedSection(
              delay: Duration(milliseconds: index * MotionDurations.stagger.inMilliseconds),
              slideDirection: SlideDirection.topToBottom,
              visible: true,
              child: _buildTaskGroup(
                context,
                entry.key,
                entry.value,
                isDark,
                isHighContrast,
                isDesktop,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTaskGroup(
    BuildContext context,
    String period,
    List<WorkTask> tasks,
    bool isDark,
    bool isHighContrast,
    bool isDesktop,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Period header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              period,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? (isHighContrast ? Colors.white : const Color(0xFFE8EBEF))
                    : const Color(0xFF111827),
              ),
            ),
            Text(
              'Total: ${_calculateTotalDuration(tasks)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : const Color(0xFF9AA3AF))
                    : const Color(0xFF5B6472),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Divider(
          height: 1,
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFF262D37))
              : const Color(0xFFE2E6EB),
        ),
        // Task rows
        ...tasks.map(
          (task) {
            final taskIndex = tasks.indexOf(task);
            return DelayedAnimatedSection(
              delay: Duration(milliseconds: taskIndex * MotionDurations.stagger.inMilliseconds),
              slideDirection: SlideDirection.topToBottom,
              visible: true,
              child: _buildTaskRow(context, task, isDark, isHighContrast, isDesktop),
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTaskRow(
    BuildContext context,
    WorkTask task,
    bool isDark,
    bool isHighContrast,
    bool isDesktop,
  ) {
    final startedAt = task.startedAt;
    final endedAt = task.endedAt;
    final status = task.status;
    final actualMinutes = task.actualMinutes ?? 0;

    if (!isDesktop) {
      // Mobile: card layout
      return GestureDetector(
        onTap: () {
          if (status != 'DONE') {
            _handleTaskStartPressed(task);
          }
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? (isHighContrast
                      ? const Color(0xFF0D0D0D)
                      : const Color(0xFF151A21))
                : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.2)
                        : const Color(0xFF262D37))
                  : const Color(0xFFE2E6EB),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(value: status == 'DONE', onChanged: (_) {}),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: status == 'DONE'
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        Text(
                          task.category,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? (isHighContrast
                                      ? Colors.white.withValues(alpha: 0.7)
                                      : const Color(0xFF9AA3AF))
                                : const Color(0xFF5B6472),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${startedAt != null ? _formatTime(startedAt) : '--:--'} - ${endedAt != null ? _formatTime(endedAt) : '--:--'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    _formatDuration(actualMinutes),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Desktop: table row
    return GestureDetector(
      onTap: () {
        if (status != 'DONE') {
          _handleTaskStartPressed(task);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFF262D37))
                  : const Color(0xFFE2E6EB),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Checkbox(value: status == 'DONE', onChanged: (_) {}),
            ),
            Expanded(
              flex: 3,
              child: Text(
                task.title,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  decoration: status == 'DONE'
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
            SizedBox(
              width: 140,
              child: Text(
                task.category,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? (isHighContrast
                            ? Colors.white.withValues(alpha: 0.8)
                            : const Color(0xFF9AA3AF))
                      : const Color(0xFF5B6472),
                ),
              ),
            ),
            Expanded(
              child: Text(
                '${startedAt != null ? _formatTime(startedAt) : '--:--'} - ${endedAt != null ? _formatTime(endedAt) : '--:--'}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                _formatDuration(actualMinutes),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.more_vert, size: 18),
                onPressed: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<WorkTask> _applyFiltersToTasks() {
    // Get tasks from WorkSessionProvider instead of local state
    final sessionProvider = Provider.of<WorkSessionProvider>(context);
final tasksFromProvider = sessionProvider.state.tasks;

    var filtered = List<WorkTask>.from(tasksFromProvider);

    // Search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((task) {
final title = task.title.toLowerCase();
final category = task.category.toLowerCase();
        return title.contains(query) || category.contains(query);
      }).toList();
    }

    // Category
    if (_selectedFilterCategory != null) {
      filtered = filtered
          .where((task) => task.category == _selectedFilterCategory)
          .toList();
    }

    // Status
    if (_selectedFilterStatus != null) {
      filtered = filtered
          .where((task) => task.status == _selectedFilterStatus)
          .toList();
    }

    // Date range
    if (_dateRangeFilter != 'All Time') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      filtered = filtered.where((task) {
        final taskDate = task.endedAt ?? task.startedAt;
        if (taskDate == null) return false;
        final taskDay = DateTime(taskDate.year, taskDate.month, taskDate.day);

        switch (_dateRangeFilter) {
          case 'Today':
            return taskDay.isAtSameMomentAs(today);
          case 'Yesterday':
            return taskDay.isAtSameMomentAs(
              today.subtract(const Duration(days: 1)),
            );
          case 'Last 7 Days':
            return taskDay.isAfter(today.subtract(const Duration(days: 7)));
          case 'Last 30 Days':
          default:
            return true;
        }
      }).toList();
    }

    // Sorting
    switch (_sortBy) {
      case 'Recently Worked':
        filtered.sort((a, b) => _sortAscending
            ? (b.endedAt ?? b.startedAt ?? DateTime(0))
                .compareTo(a.endedAt ?? a.startedAt ?? DateTime(0))
            : (a.endedAt ?? a.startedAt ?? DateTime(0))
                .compareTo(b.endedAt ?? b.startedAt ?? DateTime(0)));
        break;
      case 'Recently Created':
        // Note: We don't have a createdAt field, so we're using startedAt as an approximation
        filtered.sort((a, b) => _sortAscending
            ? (b.startedAt ?? DateTime(0)).compareTo(a.startedAt ?? DateTime(0))
            : (a.startedAt ?? DateTime(0)).compareTo(b.startedAt ?? DateTime(0)));
        break;
      case 'Longest Time':
        filtered.sort((a, b) => _sortAscending
            ? (b.actualMinutes ?? 0).compareTo(a.actualMinutes ?? 0)
            : (a.actualMinutes ?? 0).compareTo(b.actualMinutes ?? 0));
        break;
      case 'Alphabetical':
        filtered.sort((a, b) => _sortAscending
            ? b.title.toLowerCase().compareTo(a.title.toLowerCase())
            : a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
    }

    return filtered;
  }

  Map<String, List<WorkTask>> _groupTasksByPeriod(
    List<WorkTask> tasks,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastWeek = today.subtract(const Duration(days: 7));
    final lastMonth = today.subtract(const Duration(days: 30));

    final groups = <String, List<WorkTask>>{
      'Today': [],
      'Yesterday': [],
      'Last 7 Days': [],
      'Last 30 Days': [],
      'Older': [],
    };

    for (final task in tasks) {
      final taskDate = task.endedAt ?? task.startedAt;
      if (taskDate == null) continue;

      final taskDay = DateTime(taskDate.year, taskDate.month, taskDate.day);

      if (taskDay.isAtSameMomentAs(today)) {
        groups['Today']!.add(task);
      } else if (taskDay.isAtSameMomentAs(yesterday)) {
        groups['Yesterday']!.add(task);
      } else if (taskDay.isAfter(lastWeek) && taskDay.isBefore(yesterday)) {
        groups['Last 7 Days']!.add(task);
      } else if (taskDay.isAfter(lastMonth) && taskDay.isBefore(lastWeek)) {
        groups['Last 30 Days']!.add(task);
      } else {
        groups['Older']!.add(task);
      }
    }

    groups.removeWhere((key, value) => value.isEmpty);
    return groups;
  }

  String _calculateTotalDuration(List<WorkTask> tasks) {
    final totalMinutes = tasks.fold<int>(
      0,
      (sum, task) => sum + (task.actualMinutes ?? 0),
    );
    return _formatDuration(totalMinutes);
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12
        ? time.hour - 12
        : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _formatElapsedTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _handleTaskStartPressed(WorkTask task) async {
    final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
    final workService = WorkService();

    // If no active work session, start one automatically
    if (!sessionProvider.state.isActive) {
      try {
        await sessionProvider.startShift();
      } catch (e) {
        if (mounted) {
          // Error handling removed; error is reflected in provider state via StateDisplay
        }
        return;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) {
      if (mounted) {
        // Error handling removed; error is reflected in provider state via StateDisplay
      }
      return;
    }

    try {
      // If there's a current task and it's different from the one we're starting, pause it
      final currentTask = sessionProvider.currentTask;
      if (currentTask != null && currentTask.id != task.id) {
        // Pause current task by setting to BLOCKED
        await workService.updateTaskStatus(token, currentTask.id, 'BLOCKED');
      }

      // Start the selected task (set to IN_PROGRESS)
      await workService.startTask(token, task.id);

      // Set as current task in provider
      sessionProvider.setCurrentTask(task);

      // Refresh to get updated task status from backend
      await sessionProvider.refresh();
    } catch (e) {
      if (mounted) {
        // Error handling removed; error is reflected in provider state via StateDisplay
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  void _handleStartPressed() async {
    if (_selectedCategory == 'Other' && _effectiveCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a category for Other.')),
      );
      return;
    }
    if (_isTimerMode) {
      // Timer mode: start work session if none exists, then start/task switch
      final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
      final workService = WorkService();

      // If no active work session, start one automatically
      if (!sessionProvider.state.isActive) {
        try {
          await sessionProvider.startShift();
        } catch (e) {
          if (mounted) {
            // Error handling removed; error is reflected in provider state via StateDisplay
          }
          return;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        if (mounted) {
          // Error handling removed; error is reflected in provider state via StateDisplay
        }
        return;
      }

      // Get or create the task from the entry bar
      final taskTitle = _taskTitleController.text.trim();
      if (taskTitle.isEmpty) {
        if (mounted) {
          // Error handling removed; error is reflected in provider state via StateDisplay
        }
        return;
      }

      WorkTask? taskToStart;
      bool isNewTask = false;

      // Look for existing task with matching title and category in current session
final matchingTasks = sessionProvider.state.tasks.where((task) {
        return task?.title == taskTitle &&
            task?.category == _effectiveCategory &&
            (task?.status == 'TODO' || task?.status == 'IN_PROGRESS' || task?.status == 'BLOCKED');
      }).toList();

      if (matchingTasks.isNotEmpty) {
        // Use the most recently updated matching task
        taskToStart = matchingTasks.first;
      } else {
        // Create a new task
        isNewTask = true;
        try {
          final taskResponse = await workService.createTask(token, {
            'title': taskTitle,
            'category': _effectiveCategory,
            'work_session_id': sessionProvider.state.session?.id,
          });
          taskToStart = WorkTask.fromJson(taskResponse);
        } catch (e) {
          if (mounted) {
            // Error handling removed; error is reflected in provider state via StateDisplay
          }
          return;
        }
      }

      // Task switching: pause current task if it's different from the one we're starting
      final currentTask = sessionProvider.currentTask;
      if (currentTask != null && currentTask.id != taskToStart!.id) {
        try {
          // Pause current task by setting to BLOCKED (preserves start time)
          await workService.updateTaskStatus(token, currentTask.id, 'BLOCKED');
        } catch (e) {
          if (mounted) {
            // Error handling removed; error is reflected in provider state via StateDisplay
          }
          return;
        }
      }

      // Start the selected task (set to IN_PROGRESS)
      try {
        await workService.startTask(token, taskToStart!.id);

        // Set as current task in provider
        sessionProvider.setCurrentTask(taskToStart);

        // Clear the entry bar for next task
        if (isNewTask) {
          _taskTitleController.clear();
        }

        // Refresh to get updated task status from backend
        await sessionProvider.refresh();
      } catch (e) {
        if (mounted) {
          // Error handling removed; error is reflected in provider state via StateDisplay
        }
        return;
      }

      // Timer UI state is now handled by the rebuild - no local timer state needed
      if (mounted) {
        setState(() {});
      }
    } else {
      _saveManualTask();
    }
  }

  Future<void> _saveManualTask() async {
    final title = _taskTitleController.text.trim();
    if (title.isEmpty) {
      // Error handling removed; error is reflected in provider state via StateDisplay
      return;
    }
    if (_selectedCategory == 'Other' && _effectiveCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a category for Other.')),
      );
      return;
    }

    final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);

    setState(() => _isCreating = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) return;
      if (!mounted) return;
      if (!sessionProvider.state.isActive) {
        // Error handling removed; error is reflected in provider state via StateDisplay
        return;
      }

      final taskResponse = await _workService.createTask(token, {
        'title': title,
        'category': _effectiveCategory ?? 'Content Creation',
      });
        if (!mounted) return;

      // Transition through lifecycle: started → in_progress → done
      // started_at and ended_at are set by backend during status transitions
      final taskId = taskResponse['id'].toString();
      await _workService.updateTaskStatus(token, taskId, 'IN_PROGRESS');
      await _workService.updateTaskStatus(token, taskId, 'DONE');

      // If this was the current task, clear it since it's now done
      if (!mounted) return;
      if (sessionProvider.currentTask?.id == taskId) {
        sessionProvider.setCurrentTask(null);
      }

      _taskTitleController.clear();
      _selectedDate = null;
      _startTime = null;
      _endTime = null;
      // Refresh the session to get updated task list from backend
      await sessionProvider.refresh();
    } catch (e) {
      // Error handling removed; error is reflected in provider state via StateDisplay
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }
}
