import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/admin_service.dart';

class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  final AdminService _adminService = AdminService();
  bool _isLoading = true;
  String? _error;
  List<dynamic> _leaveTypes = [];
  String? _token;

  @override
  void initState() {
    super.initState();
    _loadTokenAndLeaveTypes();
  }

  Future<void> _loadTokenAndLeaveTypes() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (!mounted) return;
    setState(() {
      _token = token;
    });

    if (token != null) {
      try {
        final types = await _adminService.listLeaveTypes(token);
        if (!mounted) return;
        setState(() {
          _leaveTypes = types;
          _isLoading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showAddEditLeaveTypeDialog({Map<String, dynamic>? existingType}) {
    final TextEditingController nameController = TextEditingController(text: existingType?['name'] ?? '');
    final TextEditingController sortController = TextEditingController(text: existingType?['sort_order']?.toString() ?? '0');
    bool requiresDoc = existingType?['requires_documentation'] ?? false;
    bool isActive = existingType?['is_active'] ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existingType == null ? 'Add Leave Type' : 'Edit Leave Type'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Leave Type Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: sortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sort Order',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('Requires Documentation'),
                  value: requiresDoc,
                  onChanged: (val) => setDialogState(() => requiresDoc = val ?? false),
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  title: const Text('Is Active'),
                  value: isActive,
                  onChanged: (val) => setDialogState(() => isActive = val ?? true),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_token == null) return;
                try {
                  final name = nameController.text.trim();
                  final sortOrder = int.tryParse(sortController.text.trim()) ?? 0;
                  if (name.isEmpty) return;

                  if (existingType == null) {
                    await _adminService.createLeaveType(_token!, name, requiresDoc, sortOrder, isActive);
                  } else {
                    await _adminService.updateLeaveType(
                      _token!,
                      existingType['id'],
                      name: name,
                      requiresDocumentation: requiresDoc,
                      isActive: isActive,
                      sortOrder: sortOrder,
                    );
                  }

                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(existingType == null ? 'Leave type created.' : 'Leave type updated.')),
                    );
                    _loadTokenAndLeaveTypes();
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to save leave type: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: Text(existingType == null ? 'Create' : 'Save'),
            ),
          ],
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

    return Scaffold(
      backgroundColor: isDark
          ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF1A1A1A))
          : Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isDesktop ? 32 : 24),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.settings,
                              size: 28,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'System Settings & Leave Administration',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showAddEditLeaveTypeDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Leave Type'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Leave Types Administration Card
                    DesignSystem.premiumCard(
                      context: context,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Leave Types Configuration',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Manage organization leave types available for employee requests and attendance tracking.',
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                            const SizedBox(height: 20),
                            _isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : _error != null
                                    ? Text('Error loading leave types: $_error', style: const TextStyle(color: Colors.red))
                                    : _leaveTypes.isEmpty
                                        ? const Text('No leave types configured.', style: TextStyle(color: Colors.grey))
                                        : ListView.builder(
                                            shrinkWrap: true,
                                            physics: const NeverScrollableScrollPhysics(),
                                            itemCount: _leaveTypes.length,
                                            itemBuilder: (context, index) {
                                              final lt = _leaveTypes[index];
                                              final isActive = lt['is_active'] ?? true;
                                              return Card(
                                                margin: const EdgeInsets.only(bottom: 8),
                                                child: ListTile(
                                                  title: Text(lt['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                                  subtitle: Text(
                                                    'Sort Order: ${lt['sort_order']} • Requires Docs: ${lt['requires_documentation'] == true ? 'Yes' : 'No'}',
                                                  ),
                                                  trailing: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Chip(
                                                        label: Text(isActive ? 'Active' : 'Inactive'),
                                                        backgroundColor: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                                                        labelStyle: TextStyle(
                                                          color: isActive ? Colors.green.shade800 : Colors.grey.shade700,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      IconButton(
                                                        icon: const Icon(Icons.edit, size: 18),
                                                        onPressed: () => _showAddEditLeaveTypeDialog(existingType: lt),
                                                      ),
                                                      Switch(
                                                        value: isActive,
                                                        onChanged: (val) async {
                                                          if (_token == null) return;
                                                          try {
                                                            await _adminService.updateLeaveType(
                                                              _token!,
                                                              lt['id'],
                                                              isActive: val,
                                                            );
                                                            _loadTokenAndLeaveTypes();
                                                          } catch (e) {
                                                            if (context.mounted) {
                                                              ScaffoldMessenger.of(context).showSnackBar(
                                                                SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
                                                              );
                                                            }
                                                          }
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Info card
                    DesignSystem.premiumCard(
                      context: context,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 48,
                              color: DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.info,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'System Configuration',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'System-wide settings for IntelliBreak are configured '
                              'through environment variables and configuration files '
                              'on the server, not through the application interface.',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade600,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Configurable Settings:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildSettingItem(
                              context,
                              'Database Connection',
                              'DATABASE_URL environment variable',
                              isDark,
                              isHighContrast,
                            ),
                            _buildSettingItem(
                              context,
                              'Security Settings',
                              'SECRET_KEY, ALGORITHM, ACCESS_TOKEN_EXPIRE_MINUTES',
                              isDark,
                              isHighContrast,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingItem(
    BuildContext context,
    String label,
    String value,
    bool isDark,
    bool isHighContrast,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
