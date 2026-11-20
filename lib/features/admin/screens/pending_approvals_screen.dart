import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  Set<String> _approvingIds = {}; // in-flight guard
  List<dynamic> _pendingUsers = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
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

        // Load pending users data
        await _loadPendingUsers(token);
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

  Future<void> _loadPendingUsers(String token) async {
    try {
      final pendingUsers = await _apiService.getPendingUsers(token);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _pendingUsers = pendingUsers;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _refreshData() async {
    await _loadInitialData();
  }

  Future<void> _approveUser(String userId) async {
    if (_approvingIds.contains(userId)) return; // guard against duplicate
    setState(() => _approvingIds.add(userId));
    try {
      final token = await _apiService.getToken();
      if (token == null) {
        setState(() => _approvingIds.remove(userId));
        return;
      }
      await _apiService.approveUser(token, userId);
      // Remove approved user from pending list immediately; do not refresh full list (avoids duplicate call)
      if (mounted) {
        setState(() {
          _pendingUsers.removeWhere((u) => u['id'] == userId);
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User approved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to approve user: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _approvingIds.remove(userId));
      }
    }
  }

  Future<void> _rejectUser(String userId) async {
    try {
      final token = await _apiService.getToken();
      if (token == null) return;

      await _apiService.rejectUser(token, userId);
      await _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User rejected successfully')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to reject user: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context)
        .isHighContrast;

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorView(isDark, isHighContrast)
          : _pendingUsers.isEmpty
          ? _buildEmptyState(isDark, isHighContrast)
          : _buildPendingUsersList(isDark, isHighContrast),
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
              'Error Loading Pending Approvals',
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

  Widget _buildEmptyState(bool isDark, bool isHighContrast) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(48),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_search,
              size: 64,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white.withValues(alpha: 0.5)
                        : Color(0xFF9AA3AF))
                  : Colors.grey.shade400,
            ),
            const SizedBox(height: 24),
            Text(
              'No Pending Approvals',
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
              'All user accounts are up to date.',
              style: TextStyle(
                fontSize: 16,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : Color(0xFF9AA3AF))
                    : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingUsersList(bool isDark, bool isHighContrast) {
    return ListView.builder(
      itemCount: _pendingUsers.length,
      itemBuilder: (context, index) {
        final user = _pendingUsers[index];
        return _buildPendingUserCard(user, isDark, isHighContrast);
      },
    );
  }

  Widget _buildPendingUserCard(dynamic user, bool isDark, bool isHighContrast) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark
          ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF151A21))
          : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${user['full_name'] ?? 'N/A'}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? (isHighContrast ? Colors.white : Color(0xFFE8EBEF))
                    : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user['email'] ?? 'N/A',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : Color(0xFF9AA3AF))
                    : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Job Role: ${user['job_role'] ?? 'N/A'}',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.7)
                          : Color(0xFF9AA3AF))
                    : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Registered: ${user['created_at'] ?? 'N/A'}',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.5)
                          : Color(0xFF9AA3AF))
                    : Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _approvingIds.contains(user['id']) ? null : () => _approveUser(user['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.success,
                      ),
                    ),
                    child: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _rejectUser(user['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.error,
                      ),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
