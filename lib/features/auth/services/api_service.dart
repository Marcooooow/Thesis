import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intellibreak/features/dashboard/models/profile_model.dart';
import 'package:intellibreak/core/config/api_config.dart';

class ApiService {
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  static String get _baseUrl => ApiConfig.baseUrl;

  /// Public getter for the configurable base URL (used by BreakCoach / Recommendation services).
  static String get baseUrl => _baseUrl;

  /// Maximum number of retry attempts for transient failures.
  static const int _maxRetries = 5;
  /// Base delay for exponential backoff.
  static const Duration _retryDelayBase = Duration(seconds: 2);
  /// Maximum delay between retries (exponential backoff caps here).
  static const Duration _retryDelayMax = Duration(seconds: 30);

  /// Map of active in-flight GET requests for request deduplication.
  static final Map<String, Future<http.Response>> _inFlightGetRequests = {};

  /// Retry on temporary network / connection failures only.
  /// Do NOT retry auth errors (401/403) or normal client errors (400/404).
  /// Handle 401 by attempting to refresh the token and retrying once.
  /// For login/refresh endpoints, a backend health check is performed first
  /// to avoid wasted retries when the server is cold-starting.
  Future<http.Response> _sendRequest(
    Future<http.Response> Function() requestFn,
    String method,
    String endpoint,
  ) async {
    if (method == 'GET') {
      if (_inFlightGetRequests.containsKey(endpoint)) {
        debugPrint('[HTTP] Deduping in-flight GET $endpoint');
        return await _inFlightGetRequests[endpoint]!;
      }
      final completer = Completer<http.Response>();
      _inFlightGetRequests[endpoint] = completer.future;
      try {
        final res = await _executeSendRequest(requestFn, method, endpoint);
        completer.complete(res);
        return res;
      } catch (e, st) {
        completer.completeError(e, st);
        rethrow;
      } finally {
        _inFlightGetRequests.remove(endpoint);
      }
    } else {
      return await _executeSendRequest(requestFn, method, endpoint);
    }
  }

  Future<http.Response> _executeSendRequest(
    Future<http.Response> Function() requestFn,
    String method,
    String endpoint,
  ) async {
    // For login and refresh endpoints, first check backend availability.
    if (endpoint == '/auth/login' || endpoint == '/auth/refresh') {
      try {
        final healthResponse = await _client
            .get(Uri.parse('$_baseUrl/health'))
            .timeout(const Duration(seconds: 5));
        if (healthResponse.statusCode != 200) {
          throw Exception(
              'Backend unavailable. The server is waking up from inactivity. '
              'Please wait and try again.');
        }
      } catch (e) {
        // Backend not reachable — do not proceed with login attempts.
        rethrow;
      }
    }

    int attempt = 0;
    bool triedRefresh = false;
    Exception lastException = Exception('Server unavailable.');

    // Adaptive timeout for heavy analytics / reporting / recommendation endpoints
    final timeoutDuration = (endpoint.contains('/analytics/') ||
                             endpoint.contains('/reports/') ||
                             endpoint.contains('/recommend/'))
        ? const Duration(seconds: 25)
        : const Duration(seconds: 10);

    while (attempt < _maxRetries) {
      try {
        final response = await requestFn().timeout(timeoutDuration);
        // Handle 401 by attempting to refresh the token and retrying once.
        if (response.statusCode == 401) {
          // Skip refresh logic for login and refresh endpoints to avoid unintended behavior.
          if (endpoint == '/auth/refresh' || endpoint == '/auth/login') {
            return response;
          }
          if (!triedRefresh) {
            triedRefresh = true;
            try {
              await refreshAccessToken();
              // Retry the original request with the new token.
              // Do not increment attempt because we want to retry within the same attempt limit.
              continue;
            } catch (e) {
              lastException = Exception('Failed to refresh token: $e');
              break;
            }
          } else {
            // We have already tried to refresh and we still got 401.
            lastException =
              Exception('Refresh token expired or revoked. Please sign in again.');
            break;
          }
        }
        // Do not retry successful or auth/client error responses.
        return response;
      } on TimeoutException catch (_) {
        attempt++;
        debugPrint('[HTTP] $method $endpoint timeout (attempt $attempt/$_maxRetries)');
        if (attempt >= _maxRetries) {
          lastException = Exception(
              'Server unavailable: connection timed out after $_maxRetries attempts. '
              'Please wait and try again.');
          break;
        }
        // Exponential backoff: 2s, 4s, 8s, ... capped at 30s
        final delay = _retryDelayBase * (1 << (attempt - 1));
        final cappedDelay = delay > _retryDelayMax ? _retryDelayMax : delay;
        debugPrint('[HTTP] Backoff before retry: ${cappedDelay.inSeconds}s');
        await Future.delayed(cappedDelay);
        continue;
      } catch (e) {
        final msg = e.toString();
        // Retry only connection-level failures (not auth/client errors).
        final isConnectionFailure = msg.contains('Failed to fetch') ||
            msg.contains('SocketException') ||
            msg.contains('Connection refused') ||
            msg.contains('Network is unreachable');
        if (isConnectionFailure) {
          attempt++;
          debugPrint('[HTTP] $method $endpoint connection failure (attempt $attempt/$_maxRetries): $msg');
          if (attempt >= _maxRetries) {
            lastException = Exception(
                'Failed to reach server: please check your connection (after $_maxRetries attempts).');
            break;
          }
          // Exponential backoff: 2s, 4s, 8s, ... capped at 30s
          final delay = _retryDelayBase * (1 << (attempt - 1));
          final cappedDelay = delay > _retryDelayMax ? _retryDelayMax : delay;
          debugPrint('[HTTP] Backoff before retry: ${cappedDelay.inSeconds}s');
          await Future.delayed(cappedDelay);
          continue;
        }
        // Non-retryable error — translate correctly, never as connection failure.
        debugPrint('[HTTP] $method $endpoint Error: $e');
        if (msg.contains('Failed to fetch') || msg.contains('SocketException') ||
            msg.contains('Connection refused') || msg.contains('Network is unreachable')) {
          throw Exception('Failed to reach server: please check your connection.');
        }
        // HTTP/auth errors thrown by login/getMapWithAuth etc. — pass through as-is.
        throw Exception(msg);
      }
    }
    throw lastException;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    debugPrint('[API] Effective Base URL: $_baseUrl');
    debugPrint('[API] Login endpoint: $_baseUrl/auth/login');
    final response = await _sendRequest(
      () => _client.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ),
      'POST',
      '/auth/login',
    );
    debugPrint('[API] Login response status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (!data['requires_2fa']) {
        await _saveTokens(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token']
        );
        final restricted = data['message'] == 'Password change required';
        await _saveRestrictedFlag(restricted);
      }
      return data;
    } else if (response.statusCode == 401) {
      debugPrint('[API] Login failed 401: Unauthorized');
      throw Exception('Incorrect email or password');
    } else if (response.statusCode == 403) {
      debugPrint('[API] Login failed 403: Account not approved');
      throw Exception('Account not approved by manager');
    } else {
      debugPrint('[API] Login failed status: ${response.statusCode}');
      throw Exception('Login failed: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> changePassword(String currentPassword, String newPassword) async {
    final token = await getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await _sendRequest(
      () => _client.post(
        Uri.parse('$_baseUrl/auth/change-password'),
        headers: headers,
        body: jsonEncode({'current_password': currentPassword, 'new_password': newPassword}),
      ),
      'POST',
      '/auth/change-password',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to change password: ${response.statusCode}');
    }
  }

  /// Sets up TOTP 2FA for the authenticated user
  Future<Map<String, dynamic>> setupTotp(String token) async {
    final response = await _sendRequest(
      () => _client.post(
        Uri.parse('$_baseUrl/auth/totp/setup'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
      'POST',
      '/auth/totp/setup',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to setup TOTP: ${response.statusCode}');
    }
  }

  /// Verifies and completes TOTP 2FA setup
  Future<Map<String, dynamic>> verifyTotpSetup(
    String token,
    String totpToken,
  ) async {
    final response = await _sendRequest(
      () => _client.post(
        Uri.parse('$_baseUrl/auth/totp/verify-setup'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'token': totpToken}),
      ),
      'POST',
      '/auth/totp/verify-setup',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to verify TOTP setup: ${response.statusCode}');
    }
  }

  /// Disables TOTP 2FA for the authenticated user
  Future<Map<String, dynamic>> disableTotp(
    String token,
    String password,
    String totpToken,
  ) async {
    final response = await _sendRequest(
      () => _client.post(
        Uri.parse('$_baseUrl/auth/totp/disable'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'password': password, 'token': totpToken}),
      ),
      'POST',
      '/auth/totp/disable',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to disable TOTP: ${response.statusCode}');
    }
  }

  /// Verifies TOTP code during login challenge
  Future<Map<String, dynamic>> verifyLogin2fa(
    String challengeToken,
    String totpToken,
  ) async {
    final response = await _sendRequest(
      () => _client.post(
        Uri.parse('$_baseUrl/auth/login/2fa'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'challenge_token': challengeToken,
          'totp_token': totpToken,
        }),
      ),
      'POST',
      '/auth/login/2fa',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      return data;
    } else {
      throw Exception('Failed to verify TOTP: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getMe(String token) async {
    final response = await _sendRequest(
      () => _client.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
      'GET',
      '/auth/me',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('[NAME-TRACE-1] /auth/me full_name = "${data['full_name']}"');
      print('[NAME-TRACE-1] status = ${response.statusCode}');
      print('[NAME-TRACE-3] getMe.full_name = "${data['full_name']}"');
      return data;
    } else {
      throw Exception('Failed to fetch user info: ${response.statusCode}');
    }
  }

  Future<Profile> getProfile(String token) async {
    final json = await getMapWithAuth('/profile/me', token);
    if (json == null) {
      throw Exception('Profile not found');
    }
    return Profile.fromJson(json);
  }

  Future<Profile> updateProfile(String token, Map<String, dynamic> updateData) async {
    final json = await patchWithAuth('/profile/me', token, updateData);
    return Profile.fromJson(json);
  }

  Future<Map<String, dynamic>> register(
    String email,
    String password,
    String fullName, {
      required String role,
      String accountType = 'organization',
      String organizationName = '',
      String? jobRole,
      String? industry,
      int? yearsOfExperience,
      int? age,
      String? gender,
      String? educationAttainment,
      String? maritalStatus,
      int? targetDailyHours,
      String? shiftStartTime,
      String? shiftEndTime,
      List<String>? workDays,
      String? invitationToken,
      Map<String, dynamic>? workProfile,
    }) async {
    final requestBody = <String, dynamic>{
      'email': email,
      'password': password,
      'full_name': fullName,
      'role': role,
      'account_type': accountType,
      'organization_name': organizationName,
    };

    if (jobRole != null && jobRole.isNotEmpty) requestBody['job_role'] = jobRole;
    if (industry != null && industry.isNotEmpty) requestBody['industry'] = industry;
    if (yearsOfExperience != null) requestBody['years_of_experience'] = yearsOfExperience;
    if (age != null) requestBody['age'] = age;
    if (gender != null && gender.isNotEmpty) requestBody['gender'] = gender;
    if (educationAttainment != null && educationAttainment.isNotEmpty) requestBody['education_attainment'] = educationAttainment;
    if (maritalStatus != null && maritalStatus.isNotEmpty) requestBody['marital_status'] = maritalStatus;
    if (targetDailyHours != null) requestBody['target_daily_hours'] = targetDailyHours;
    if (shiftStartTime != null && shiftStartTime.isNotEmpty) requestBody['shift_start_time'] = shiftStartTime;
    if (shiftEndTime != null && shiftEndTime.isNotEmpty) requestBody['shift_end_time'] = shiftEndTime;
    if (workDays != null && workDays.isNotEmpty) requestBody['work_days'] = workDays;
    if (invitationToken != null && invitationToken.isNotEmpty) requestBody['invitation_token'] = invitationToken;
    if (workProfile != null && workProfile.isNotEmpty) requestBody['work_profile'] = workProfile;

    final response = await _sendRequest(
      () => _client.post(
        Uri.parse('$_baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ),
      'POST',
      '/auth/register',
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 400) {
      final errorData = jsonDecode(response.body);
      if (errorData['detail'] is String &&
          errorData['detail'].contains('Email already registered')) {
        throw Exception('An account already exists for this email.');
      } else {
        throw Exception(
          'Registration failed: ${errorData['detail'] ?? response.statusCode}',
        );
      }
    } else if (response.statusCode == 422) {
      final errorData = jsonDecode(response.body);
      if (errorData['detail'] is List && errorData['detail'].isNotEmpty) {
        final firstError = errorData['detail'][0];
        final msg = firstError['msg'] ?? 'Validation error';
        throw Exception('Validation error: $msg');
      } else {
        throw Exception('Validation failed: ${response.statusCode}');
      }
    } else {
      throw Exception('Registration failed: ${response.statusCode}');
    }
  }

  Future<void> _saveTokens({required String accessToken, String? refreshToken}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString('refresh_token', refreshToken);
    }
  }

  Future<void> _saveRestrictedFlag(bool isRestricted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_restricted_token', isRestricted);
  }

  Future<bool> _getRestrictedFlag() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_restricted_token') ?? false;
  }

  /// Get the restricted flag status from persistent storage
  /// Returns true if stored value is "true", false otherwise (including missing key)
  Future<bool> getRestrictedFlag() async {
    return _getRestrictedFlag();
  }

  Future<Map<String, dynamic>> validateInvitation(String token) async {
    final response = await _sendRequest(
      () => _client.get(
        Uri.parse('$_baseUrl/teams/invitations/validate/$token'),
        headers: {'Content-Type': 'application/json'},
      ),
      'GET',
      '/teams/invitations/validate/{token}',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to validate invitation: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await _sendRequest(
      () => _client.post(
        Uri.parse('$_baseUrl/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ),
      'POST',
      '/auth/forgot-password',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        'Failed to send reset password email: ${response.statusCode}',
      );
    }
  }

  Future<Map<String, dynamic>> resetPassword(
    String token,
    String newPassword,
  ) async {
    final response = await _sendRequest(
      () => _client.post(
        Uri.parse('$_baseUrl/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'new_password': newPassword}),
      ),
      'POST',
      '/auth/reset-password',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to reset password: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>?> getWorkProfile(String token) async {
    final response = await _sendRequest(
      () => _client.get(
        Uri.parse('$_baseUrl/work-profile/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
      'GET',
      '/work-profile/me',
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception('Failed to fetch work profile: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> saveWorkProfile(String token, Map<String, dynamic> data) async {
    final response = await _sendRequest(
      () => _client.post(
        Uri.parse('$_baseUrl/work-profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(data),
      ),
      'POST',
      '/work-profile',
    );
    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to save work profile: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> updateWorkProfile(String token, Map<String, dynamic> data) async {
    final response = await _sendRequest(
      () => _client.patch(
        Uri.parse('$_baseUrl/work-profile/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(data),
      ),
      'PATCH',
      '/work-profile/me',
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update work profile: ${response.statusCode}');
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('refresh_token');
    await prefs.setBool('is_restricted_token', false);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('refresh_token');
  }

  /// Call backend refresh endpoint and update tokens.
  /// Returns new access token or throws on failure.
  Future<String> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw Exception('No refresh token available. Please sign in again.');
    }
    final response = await _sendRequest(
      () => _client.post(
        Uri.parse('$_baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'challenge_token': refreshToken}),
      ),
      'POST',
      '/auth/refresh',
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _saveTokens(
        accessToken: data['access_token'],
        refreshToken: refreshToken,
      );
      return data['access_token'];
    } else if (response.statusCode == 401) {
      await clearToken();
      throw Exception('Refresh token expired or revoked. Please sign in again.');
    } else {
      throw Exception('Token refresh failed: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>?> getMapWithAuth(
    String endpoint,
    String token, {
    bool allowNotFound = false,
  }) async {
    final response = await _sendRequest(
      () => _client.get(
        Uri.parse('$_baseUrl$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
      'GET',
      endpoint,
    );

    if (response.statusCode == 200) {
      debugPrint('[HTTP] GET $endpoint STATUS=${response.statusCode} BODY=${response.body.substring(0, response.body.length.clamp(0, 200))}');
      return jsonDecode(response.body);
    } else if (response.statusCode == 404 && allowNotFound) {
      debugPrint('[HTTP] GET $endpoint 404 allowNotFound -> null');
      return null;
    } else {
      if (response.statusCode == 401) {
        throw Exception('Unauthorized: session expired or invalid token. Please sign in again.');
      }
      if (response.statusCode == 403) {
        throw Exception('Access denied (HTTP 403)');
      }
      debugPrint('[HTTP] GET $endpoint ERROR status=${response.statusCode} body=${response.body.substring(0, response.body.length.clamp(0, 200))}');
      throw Exception('Failed to GET $endpoint: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> get(String endpoint, String token) async {
    final response = await _sendRequest(
      () => _client.get(
        Uri.parse('$_baseUrl$endpoint'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ),
      'GET',
      endpoint,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      if (response.statusCode == 404) {
        throw Exception('Not found');
      }
      debugPrint(
        '[HTTP] GET $endpoint ERROR status=${response.statusCode} body=${response.body.substring(0, response.body.length.clamp(0, 200))}',
      );
      throw Exception('Failed to GET $endpoint: ${response.statusCode}');
    }
  }

  Future<List<dynamic>> getListWithAuth(
    String endpoint,
    String token, {
    bool allowNotFound = false,
  }) async {
    final response = await _sendRequest(
      () => _client.get(
        Uri.parse('$_baseUrl$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
      'GET',
      endpoint,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 404 && allowNotFound) {
      return [];
    } else {
      if (response.statusCode == 401) {
        throw Exception('Unauthorized: session expired or invalid token. Please sign in again.');
      }
      if (response.statusCode == 403) {
        throw Exception('Access denied (HTTP 403)');
      }
      throw Exception('Failed to GET $endpoint: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> postWithAuth(
    String endpoint,
    String token,
    Map<String, dynamic> body,
  ) async {
    debugPrint('[HTTP] POST $endpoint BEGIN');
    final response = await _sendRequest(
      () => _client.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      ),
      'POST',
      endpoint,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      debugPrint('[HTTP] POST $endpoint STATUS=${response.statusCode} BODY=${response.body.substring(0, response.body.length.clamp(0, 200))}');
      return jsonDecode(response.body);
    } else {
      debugPrint('[HTTP] POST $endpoint ERROR status=${response.statusCode} body=${response.body.substring(0, response.body.length.clamp(0, 200))}');
      throw Exception('Failed to POST $endpoint: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> patchWithAuth(
    String endpoint,
    String token,
    Map<String, dynamic> body,
  ) async {
    debugPrint('[HTTP] PATCH $endpoint BEGIN');
    final response = await _sendRequest(
      () => _client.patch(
        Uri.parse('$_baseUrl$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      ),
      'PATCH',
      endpoint,
    );

    if (response.statusCode == 200) {
      debugPrint('[HTTP] PATCH $endpoint STATUS=200 BODY=${response.body.substring(0, response.body.length.clamp(0, 200))}');
      return jsonDecode(response.body);
    } else {
      debugPrint('[HTTP] PATCH $endpoint ERROR status=${response.statusCode} body=${response.body.substring(0, response.body.length.clamp(0, 200))}');
      throw Exception('Failed to PATCH $endpoint: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>?> deleteWithAuth(
    String endpoint,
    String token,
  ) async {
    debugPrint('[HTTP] DELETE $endpoint BEGIN');
    final response = await _sendRequest(
      () => _client.delete(
        Uri.parse('$_baseUrl$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
      'DELETE',
      endpoint,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      debugPrint('[HTTP] DELETE $endpoint STATUS=${response.statusCode}');
      if (response.body.isNotEmpty) {
        return jsonDecode(response.body);
      }
      return null;
    } else {
      debugPrint('[HTTP] DELETE $endpoint ERROR status=${response.statusCode} body=${response.body.substring(0, response.body.length.clamp(0, 200))}');
      throw Exception('Failed to DELETE $endpoint: ${response.statusCode}');
    }
  }

  Future<List<dynamic>> getPendingUsers(String token) async {
    return await getListWithAuth('/admin/pending-users', token);
  }

  Future<Map<String, dynamic>> approveUser(String token, String userId) async {
    return await patchWithAuth('/admin/approve-user/$userId', token, {});
  }

  Future<Map<String, dynamic>> rejectUser(String token, String userId) async {
    return await patchWithAuth('/admin/reject-user/$userId', token, {});
  }

  Future<Map<String, dynamic>> getAuditLogsSummary(
    String token, {
    String? actionType,
    String? category,
    String? outcome,
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    String? search,
  }) async {
    final params = <String, String>{};
    if (actionType != null && actionType.isNotEmpty) {
      params['action_type'] = actionType;
    }
    if (category != null && category.isNotEmpty) {
      params['category'] = category;
    }
    if (outcome != null && outcome.isNotEmpty) {
      params['outcome'] = outcome;
    }
    if (userId != null && userId.isNotEmpty) {
      params['user_id'] = userId;
    }
    if (startDate != null) {
      params['start_date'] = startDate.toIso8601String();
    }
    if (endDate != null) {
      params['end_date'] = endDate.toIso8601String();
    }
    if (search != null && search.isNotEmpty) {
      params['search'] = search;
    }

    final queryString = params.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    final endpoint = queryString.isNotEmpty
        ? '/admin/audit-logs/summary?$queryString'
        : '/admin/audit-logs/summary';

    return (await getMapWithAuth(endpoint, token)) ?? {};
  }

  Future<List<dynamic>> getAuditLogs(
    String token, {
    int page = 1,
    int limit = 25,
    String? actionType,
    String? category,
    String? outcome,
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    String? search,
  }) async {
    final params = <String, String>{};
    params['page'] = page.toString();
    params['limit'] = limit.clamp(1, 100).toString();
    if (actionType != null && actionType.isNotEmpty) {
      params['action_type'] = actionType;
    }
    if (category != null && category.isNotEmpty) {
      params['category'] = category;
    }
    if (outcome != null && outcome.isNotEmpty) {
      params['outcome'] = outcome;
    }
    if (userId != null && userId.isNotEmpty) {
      params['user_id'] = userId;
    }
    if (startDate != null) {
      params['start_date'] = startDate.toIso8601String();
    }
    if (endDate != null) {
      params['end_date'] = endDate.toIso8601String();
    }
    if (search != null && search.isNotEmpty) {
      params['search'] = search;
    }

    final queryString = params.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    final endpoint = queryString.isNotEmpty
        ? '/admin/audit-logs?$queryString'
        : '/admin/audit-logs';

    return await getListWithAuth(endpoint, token);
  }
}