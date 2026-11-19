import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/employees/widgets/add_employee_wizard_dialog.dart';
import 'package:intellibreak/features/employees/models/employee_model.dart';
import 'package:intellibreak/features/employees/screens/manager_employee_detail_screen.dart';

class EmployeesScreenContent extends StatefulWidget {
  const EmployeesScreenContent({super.key});

  @override
  State<EmployeesScreenContent> createState() => _EmployeesScreenContentState();
}

class _EmployeesScreenContentState extends State<EmployeesScreenContent> {
  String? _token;
  bool _initialized = false;
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  String? _error;
  List<Employee> _employees = [];

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _token = token;
      _initialized = true;
    });
    if (token != null) {
      _loadEmployees();
    }
  }

  Future<void> _loadEmployees() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final token = _token;
      if (token == null) {
        throw Exception('No token available');
      }
      final List<dynamic> jsonList =
          await _apiService.getListWithAuth('/employees', token);
      final List<Employee> employees = jsonList
          .map((json) => Employee.fromJson(json as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _deactivateEmployee(String employeeId) async {
    try {
      final token = _token;
      if (token == null) {
        throw Exception('No token available');
      }
      await _apiService
          .patchWithAuth('/employees/$employeeId/deactivate', token, {});
      if (!mounted) return;
      await _loadEmployees();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to deactivate employee: $e')),
      );
    }
  }

  void _showAddEmployeeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AddEmployeeWizardDialog(
        onEmployeeCreated: _loadEmployees,
      ),
    );
  }

  void _showDeactivateConfirmationDialog(
      BuildContext context, String employeeId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate Employee'),
        content: const Text('Are you sure you want to deactivate this employee?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deactivateEmployee(employeeId);
            },
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Employee',
            onPressed: () => _showAddEmployeeDialog(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadEmployees,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Error: $_error',
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadEmployees,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _employees.isEmpty
                    ? const Center(
                        child: Text(
                          'No employees found. Click + to add one.',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _employees.length,
                        itemBuilder: (context, index) {
                          final employee = _employees[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(employee.fullName.isNotEmpty
                                    ? employee.fullName[0].toUpperCase()
                                    : 'E'),
                              ),
                              title: Text(employee.fullName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(employee.email),
                                  if (employee.teamName != null)
                                    Text('Team: ${employee.teamName}',
                                        style: const TextStyle(
                                            color: Colors.blueGrey)),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: employee.isActive
                                  ? IconButton(
                                      icon: const Icon(Icons.block,
                                          color: Colors.red),
                                      tooltip: 'Deactivate Employee',
                                      onPressed: () =>
                                          _showAddEmployeeDialogPlaceholder(
                                              context, employee.id),
                                    )
                                  : null,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ManagerEmployeeDetailScreen(
                                      employeeId: employee.id,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
      ),
    );
  }

  void _showAddEmployeeDialogPlaceholder(BuildContext context, String employeeId) {
    _showDeactivateConfirmationDialog(context, employeeId);
  }
}
