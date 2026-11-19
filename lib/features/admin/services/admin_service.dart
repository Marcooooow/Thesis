import '../../auth/services/api_service.dart';

class AdminService {
  final ApiService _apiService = ApiService();

  /// Get all users with filtering and pagination
  Future<Map<String, dynamic>> getAllUsers(
    String token, {
    int page = 1,
    int limit = 25,
    String? search,
    String? role,
    String? status,
    String? organization,
  }) async {
    // Build query parameters
    final params = <String, String>{};
    params['page'] = page.toString();
    params['limit'] = limit.clamp(1, 100).toString();
    if (search != null && search.isNotEmpty) {
      params['search'] = search;
    }
    if (role != null && role.isNotEmpty) {
      params['role'] = role;
    }
    if (status != null && status.isNotEmpty) {
      params['status'] = status;
    }
    if (organization != null && organization.isNotEmpty) {
      params['organization'] = organization;
    }

    // Build query string
    final queryString = params.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    final endpoint = queryString.isNotEmpty
        ? '/auth/admin/users?$queryString'
        : '/auth/admin/users';

    final result = await _apiService.getMapWithAuth(endpoint, token);
    return result ?? {'users': [], 'total': 0, 'page': 1, 'limit': 25, 'total_pages': 1};
  }

  /// Create a new user
  Future<Map<String, dynamic>> createUser(
    String token,
    String email,
    String password,
    String fullName, {
    String accountType = 'organization',
    String? organizationName,
    String role = 'EMPLOYEE',
  }) async {
    final response = await _apiService.postWithAuth(
      '/auth/admin/users',
      token,
      {
        'email': email,
        'password': password,
        'full_name': fullName,
        'account_type': accountType,
        if (organizationName != null && organizationName.isNotEmpty)
          'organization_name': organizationName,
        'role': role,
      },
    );
    return response;
  }

  /// Update user details
  Future<Map<String, dynamic>> updateUser(
    String token,
    String userId, {
    String? fullName,
    String? role,
    String? organizationName,
  }) async {
    final updates = <String, dynamic>{};
    if (fullName != null) {
      updates['full_name'] = fullName;
    }
    if (role != null) {
      updates['role'] = role;
    }
    if (organizationName != null) {
      updates['organization_name'] = organizationName;
    }

    final response = await _apiService.postWithAuth(
      '/auth/admin/users/$userId',
      token,
      updates,
    );
    return response;
  }

  /// Change user status (activate/deactivate)
  Future<Map<String, dynamic>> changeUserStatus(
    String token,
    String userId,
    bool isActive,
  ) async {
    final response = await _apiService.patchWithAuth(
      '/auth/admin/users/$userId/status',
      token,
      {'is_active': isActive},
    );
    return response;
  }

  /// Reset user password
  Future<Map<String, dynamic>> resetUserPassword(
    String token,
    String userId,
  ) async {
    final response = await _apiService.postWithAuth(
      '/auth/admin/users/$userId/reset-password',
      token,
      {},
    );
    return response;
  }

  /// Delete a user
  Future<Map<String, dynamic>> deleteUser(String token, String userId) async {
    final response = await _apiService.postWithAuth(
      '/auth/admin/users/$userId/delete',
      token,
      {},
    );
    return response;
  }

  /// List leave types for organization
  Future<List<dynamic>> listLeaveTypes(String token, {bool includeInactive = true}) async {
    final response = await _apiService.getListWithAuth('/admin/leave-types?include_inactive=$includeInactive', token);
    return response;
  }

  /// Create a leave type
  Future<Map<String, dynamic>> createLeaveType(String token, String name, bool requiresDocumentation, int sortOrder, bool isActive) async {
    final response = await _apiService.postWithAuth(
      '/admin/leave-types',
      token,
      {
        'name': name,
        'requires_documentation': requiresDocumentation,
        'sort_order': sortOrder,
        'is_active': isActive,
      },
    );
    return response;
  }

  /// Update a leave type
  Future<Map<String, dynamic>> updateLeaveType(
    String token,
    String leaveTypeId, {
    String? name,
    bool? requiresDocumentation,
    bool? isActive,
    int? sortOrder,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (requiresDocumentation != null) updates['requires_documentation'] = requiresDocumentation;
    if (isActive != null) updates['is_active'] = isActive;
    if (sortOrder != null) updates['sort_order'] = sortOrder;

    final response = await _apiService.patchWithAuth(
      '/admin/leave-types/$leaveTypeId',
      token,
      updates,
    );
    return response;
  }
}
