import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/services/auth_service.dart';
import '../../features/auth/services/api_service.dart';
import '../../providers/team_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/dashboard/services/work_service.dart';
import '../../features/dashboard/screens/app_shell.dart';
import '../../features/dashboard/screens/manager_shell.dart';
import '../../features/admin/screens/admin_shell.dart';
import '../../providers/work_session_provider.dart';
import '../../providers/work_session_models.dart';
import '../../features/dashboard/providers/profile_provider.dart';
import '../../providers/presence_provider.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum WelcomeBackAction { continueTask, chooseAnother }

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final WorkService _workService = WorkService();
  User? _user;
  bool _isLoading = true;
  String? _userRole;
  bool _hasBackendToken = false;
  bool _isRestrictedToken = false;
  VoidCallback? _tokenChangedCallback;

  // Welcome-back modal state: prevent multiple dialogs and track welcomed tasks in this session
  bool _isShowingWelcomeBack = false;
  final Set<String> _welcomedTaskIds = {};
  static const String _prefWelcomedTaskPrefix = 'welcomed_task_';
  static const String _prefWelcomedTaskTimestamp = 'welcomed_task_timestamp_';

  @override
  void initState() {
    super.initState();
    debugPrint('[AUTHGATE] initState');
    _checkInitialAuth();
    _tokenChangedCallback = () {
      debugPrint('[AUTHGATE] token changed callback triggered');
      _updateAuthState();
    };
    _authService.setTokenChangedCallback(_tokenChangedCallback);
    debugPrint('[AUTHGATE] token changed callback set');
  }

  @override
  void dispose() {
    debugPrint('[AUTHGATE] dispose');
    _authService.setTokenChangedCallback(null);
    super.dispose();
  }

  Future<void> _checkInitialAuth() async {
    debugPrint('[AUTHGATE] _checkInitialAuth start');
    // First check for backend JWT token (from API login)
    try {
      final token = await _apiService.getToken();
      if (token != null && mounted) {
        debugPrint('[AUTHGATE] _checkInitialAuth: token found');
        final isRestricted = await _apiService.getRestrictedFlag();
        if (isRestricted) {
          // Restricted first-login token: do not call /auth/me (401 expected); show change screen
          setState(() {
            _isRestrictedToken = true;
            _hasBackendToken = false;
            _isLoading = false;
          });
          return;
        }
        final userData = await _apiService.getMe(token);
        // Set the current user ID in TeamProvider
        if (mounted) {
          final teamProvider = Provider.of<TeamProvider>(context, listen: false);
          teamProvider.setCurrentUserId(userData['id'].toString());
        }
        // Load the current user's profile (single source of truth for schedule)
        if (mounted) {
          final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
          await profileProvider.loadProfile();
        }
        // Restore the active work session via WorkSessionProvider (single source of truth).
        // WorkSessionProvider.refresh() fetches the session, active break, and tasks,
        // and preserves the timer by using the server's started_at.
        await _restoreActiveSession(token);

        // Initialize providers that need authentication
        if (mounted) {
          final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
          sessionProvider.initialize();
          final presenceProvider = Provider.of<PresenceProvider>(context, listen: false);
          presenceProvider.initialize();
        }

        setState(() {
          _userRole = userData['role'];
          _hasBackendToken = true;
          _isRestrictedToken = userData['must_change_password'] ?? false;
          _isLoading = false;
        });
        debugPrint('[AUTHGATE] _checkInitialAuth: set hasBackendToken=true, role=$_userRole, isLoading=false');
        // Schedule the unfinished task check after the frame.
        if (mounted) {
          SchedulerBinding.instance.addPostFrameCallback((_) async {
            if (mounted) {
              await _checkForUnfinishedTask(token);
            }
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('[AUTHGATE] _checkInitialAuth: error checking token: $e');
      // Token is invalid or expired, clear it
      await _apiService.clearToken();
      // Clear welcomed tasks for this session when we lose the token
      _welcomedTaskIds.clear();
    }

    // If no backend token, check Firebase Auth state
    debugPrint('[AUTHGATE] _checkInitialAuth: calling _setupAuthListener');
    _setupAuthListener();
  }

  /// Refresh the WorkSessionProvider's state from the backend.
  /// This is the single restoration path - the provider becomes the source of truth.
  Future<void> _restoreActiveSession(String token) async {
    try {
      final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
      await sessionProvider.refresh(token: token);
    } catch (e) {
      // If there's an error, clear the state
      if (mounted) {
        final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
        sessionProvider.clear();
      }
    }
  }

  /// Check for unfinished tasks (status == IN_PROGRESS in a previous session)
  /// and show the welcome-back modal if found.
  Future<void> _checkForUnfinishedTask(String token) async {
    // Prevent showing multiple dialogs
    if (_isShowingWelcomeBack) return;
    try {
      final tasksHistory = await _workService.getTasksHistory(token);
      if (!mounted) return;

      // Filter to IN_PROGRESS tasks and sort by startedAt descending (most recent first)
      final unfinishedTasks = tasksHistory
          .where((task) => task['status'] == 'IN_PROGRESS')
          .map((task) => WorkTask.fromJson(task))
          .where((task) => task.startedAt != null) // Only consider tasks with valid start time
          .toList()
        ..sort((a, b) => b.startedAt!.compareTo(a.startedAt!)); // Descending order (most recent first)

      if (unfinishedTasks.isNotEmpty) {
        final mostRecentUnfinished = unfinishedTasks.first;

        // Don't prompt for tasks that are part of the current active session
        if (!mounted) return;
        final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
        if (sessionProvider.state.session?.id == mostRecentUnfinished.workSessionId) {
          // This task is part of the current active session, no need to show welcome back
          return;
        }

        // Check persistent storage for already-welcomed task (survives refresh)
        final prefs = await SharedPreferences.getInstance();
        final welcomedTimestampStr = prefs.getString('$_prefWelcomedTaskTimestamp${mostRecentUnfinished.id}');
        if (welcomedTimestampStr != null) {
          try {
            final welcomedTimestamp = DateTime.parse(welcomedTimestampStr);
            // If welcomed in the last 24 hours, don't show again
            if (DateTime.now().difference(welcomedTimestamp).inHours < 24) {
              _welcomedTaskIds.add(mostRecentUnfinished.id);
              return;
            }
          } catch (_) {
            // Invalid timestamp, proceed to show dialog
          }
        }

        // Check in-memory set as fallback
        if (_welcomedTaskIds.contains(mostRecentUnfinished.id)) {
          return;
        }

        _isShowingWelcomeBack = true;
        final result = await showDialog<WelcomeBackAction>(
          context: context,
          barrierDismissible: false, // Prevent dismissing by tapping outside
          builder: (BuildContext dialogContext) {
            return WelcomeBackDialog(
              unfinishedTask: mostRecentUnfinished,
              onContinue: () => WelcomeBackAction.continueTask,
              onChooseAnother: () => WelcomeBackAction.chooseAnother,
            );
          },
        );

        if (!mounted) {
          _isShowingWelcomeBack = false;
          return;
        }

        // Mark as welcomed for this session (both in-memory and persistent)
        _welcomedTaskIds.add(mostRecentUnfinished.id);
        final prefs2 = await SharedPreferences.getInstance();
        await prefs2.setString('$_prefWelcomedTaskTimestamp${mostRecentUnfinished.id}', DateTime.now().toIso8601String());

        if (result == WelcomeBackAction.continueTask) {
          if (!mounted) return;
          debugPrint('[RESUME] 1 Continue Task entered');
          debugPrint('[RESUME] taskId=${mostRecentUnfinished.id}');
          final sessionProvider = Provider.of<WorkSessionProvider>(context, listen: false);
          final workService = WorkService();

          debugPrint('[RESUME] activeSessionBefore=${sessionProvider.state.session?.id}');
          debugPrint('[RESUME] currentTaskBefore=${sessionProvider.state.currentTask?.id}');
          debugPrint('[RESUME] providerIsRunningBefore=${sessionProvider.state.isActive}');
          debugPrint('[RESUME] providerStartTimeBefore=${sessionProvider.state.startTime}');

          final token = await _apiService.getToken();
          if (!mounted || token == null) {
            debugPrint('[RESUME] ERROR: token null');
            return;
          }
          debugPrint('[RESUME] 2 token acquired');

          // Refresh session provider to get current backend state before checking active session
          debugPrint('[RESUME] 3 refreshing provider before active-session check');
          await sessionProvider.refresh();
          debugPrint('[RESUME] 4 refresh completed');
          debugPrint('[RESUME] 4a sessionId=${sessionProvider.state.session?.id}');
          debugPrint('[RESUME] 4b isActive=${sessionProvider.state.isActive}');
          debugPrint('[RESUME] 4c startTime=${sessionProvider.state.startTime}');

          // If there's a current task and it's different from the one we are starting, pause it
          final currentTask = sessionProvider.state.currentTask;
          if (currentTask != null && currentTask.id != mostRecentUnfinished.id) {
            debugPrint('[RESUME] pausing current task ${currentTask.id}');
            try {
              await workService.updateTaskStatus(token, currentTask.id, 'BLOCKED');
            } catch (e) {
              debugPrint('[RESUME] ERROR pausing task: $e');
              if (!mounted) return;
              return;
            }
          }

          // If there's no active work session, start one.
          if (!sessionProvider.state.isActive) {
            debugPrint('[RESUME] 5 about to call startShift');
            try {
              await sessionProvider.startShift();
            } catch (e) {
              debugPrint('[RESUME] ERROR starting shift: $e');
              if (!mounted) return;
              return;
            }
            debugPrint('[RESUME] 6 startShift completed');
            debugPrint('[RESUME] 6a sessionId=${sessionProvider.state.session?.id}');
            debugPrint('[RESUME] 6b isActive=${sessionProvider.state.isActive}');
            debugPrint('[RESUME] 6c startTime=${sessionProvider.state.startTime}');
            if (!mounted) return;
          } else {
            debugPrint('[RESUME] active session already present');
          }

          debugPrint('[RESUME] 7 about to startTask taskId=${mostRecentUnfinished.id}');
          // Start the selected task (set to IN_PROGRESS)
          try {
            await workService.startTask(token, mostRecentUnfinished.id);
          } catch (e) {
            debugPrint('[RESUME] ERROR starting task: $e');
            if (!mounted) return;
            return;
          }
          debugPrint('[RESUME] 8 startTask completed');

          // Set as current task in provider
          if (!mounted) return;
          sessionProvider.setCurrentTask(mostRecentUnfinished);
          debugPrint('[RESUME] 9 setCurrentTask completed');
          debugPrint('[RESUME] 9a currentTaskId=${sessionProvider.state.currentTask?.id}');
          debugPrint('[RESUME] 9b currentTaskTitle=${sessionProvider.state.currentTask?.title}');

          // Refresh to get updated task status from backend
          if (!mounted) return;
          debugPrint('[RESUME] 10 final refresh BEGIN');
          await sessionProvider.refresh();
          debugPrint('[RESUME] 10 final state');
          debugPrint('[RESUME] 10a sessionId=${sessionProvider.state.session?.id}');
          debugPrint('[RESUME] 10b isActive=${sessionProvider.state.isActive}');
          debugPrint('[RESUME] 10c startTime=${sessionProvider.state.startTime}');
          debugPrint('[RESUME] 10d currentTaskId=${sessionProvider.state.currentTask?.id}');

          debugPrint('[RESUME] 11 Continue Task flow completed');
          debugPrint('[RESUME] task-start flow completed');
          debugPrint('[RESUME] activeSessionAfter=${sessionProvider.state.session?.id}');
          debugPrint('[RESUME] currentTaskAfter=${sessionProvider.state.currentTask?.id}');
          debugPrint('[RESUME] providerIsRunningAfter=${sessionProvider.state.isActive}');
          debugPrint('[RESUME] providerStartTimeAfter=${sessionProvider.state.startTime}');
          debugPrint('[RESUME] providerIsOnBreak=${sessionProvider.state.isOnBreak}');
          debugPrint('[RESUME] timerRunningAfter=${sessionProvider.state.elapsedTimeInSeconds != null}');
        }
        // If chooseAnother, we still mark as welcomed to prevent re-prompting on refresh

        setState(() {
          // No need to set any welcome-back state here
        });
        _isShowingWelcomeBack = false;
      }
    } catch (e) {
      // Silent failure - welcome modal is optional
      debugPrint('AuthGate: Failed to check for unfinished task: $e');
      if (mounted) {
        _isShowingWelcomeBack = false;
      }
    }
  }

  void _setupAuthListener() {
    debugPrint('[AUTHGATE] _setupAuthListener called');
    _authService.authStateChanges.listen((User? user) async {
      if (!mounted) return;
      debugPrint('[AUTHGATE] listener: Firebase user changed: $user');
      debugPrint('[AUTHGATE] authentication state changed from Firebase');
      if (_hasBackendToken) {
        // Already authenticated via backend, ignore Firebase changes
        debugPrint('[AUTHGATE] ignoring Firebase change because hasBackendToken is true');
        return;
      }

      setState(() {
        _user = user;
        _isLoading = true; // We are checking token
      });
      debugPrint('[AUTHGATE] set _user=$_user, isLoading=true');

      if (user != null) {
        // Firebase user exists, check if they have backend access
        try {
          final token = await _apiService.getToken();
          debugPrint('[AUTHGATE] Firebase user present, checking for backend token: $token');
          if (token != null) {
            final userData = await _apiService.getMe(token);
            // Restore active session from backend before rendering shell
            await _restoreActiveSession(token);
            if (mounted) {
              setState(() {
                _userRole = userData['role'];
                _hasBackendToken = true;
                _isRestrictedToken = userData['must_change_password'] ?? false;
                _isLoading = false;
              });
              debugPrint('[AUTHGATE] setState from Firebase listener: hasBackendToken=true, userRole=$_userRole, isLoading=false');
              // Schedule the unfinished task check after the frame.
              if (mounted) {
                SchedulerBinding.instance.addPostFrameCallback((_) async {
                  if (mounted) {
                    await _checkForUnfinishedTask(token);
                  }
                });
              }
            }
          } else {
            // No backend token - check if this is an anonymous (guest) user
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
              debugPrint('[AUTHGATE] setState from Firebase listener: isLoading=false (no backend token)');

              // Check if user is anonymous (guest)
              if (user.isAnonymous) {
                // Guest user - show login screen with "Continue as Guest" option
                // For now, we'll go directly to demo shell but this could be enhanced
                // with a login screen that has a "Continue as Guest" button
                if (mounted) {
                  // We'll handle guest routing in the build method based on user state
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[AUTHGATE] error in Firebase listener: $e');
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            debugPrint('[AUTHGATE] setState from Firebase listener: isLoading=false (error)');
          }
        }
      } else {
        // Firebase user is null
        if (mounted) {
          setState(() {
            _userRole = null;
            _hasBackendToken = false;
            _isLoading = false;
          });
          debugPrint('[AUTHGATE] setState from Firebase listener: hasBackendToken=false, userRole=null, isLoading=false (Firebase user null)');
          // Clear welcomed tasks for this session when we lose the backend token
          _welcomedTaskIds.clear();
        }
      }
    });
  }

  Future<void> _updateAuthState() async {
    debugPrint('[AUTHGATE] _updateAuthState start');
    final token = await _apiService.getToken();
    final hasToken = token != null && token.isNotEmpty;
    debugPrint('[AUTHGATE] checking JWT: present=$hasToken');
    if (hasToken) {
      try {
        final userData = await _apiService.getMe(token);
        if (mounted) {
          debugPrint('[AUTHGATE] userRole from token: ${userData['role']}');
          setState(() {
            _hasBackendToken = true;
            _userRole = userData['role'];
            _isLoading = false;
          });
          debugPrint('[AUTHGATE] setState: hasBackendToken=true, userRole=$_userRole, isLoading=false');
          debugPrint('[AUTHGATE] authenticated=true');
        }
      } catch (e) {
        if (mounted) {
          debugPrint('[AUTHGATE] error validating token: $e');
          setState(() {
            _hasBackendToken = false;
            _userRole = null;
            _isLoading = false;
          });
          debugPrint('[AUTHGATE] setState: hasBackendToken=false, userRole=null, isLoading=false');
          debugPrint('[AUTHGATE] authenticated=false');
        }
        // Clear work session provider when we lose backend token
        if (mounted) {
          final sessionProvider =
              Provider.of<WorkSessionProvider>(context, listen: false);
          sessionProvider.clear();
          debugPrint('[AUTHGATE] WorkSessionProvider cleared in _updateAuthState catch');
          // Clear welcomed tasks for this session when we lose the token
          _welcomedTaskIds.clear();
        }
      }
    } else {
      if (mounted) {
        debugPrint('[AUTHGATE] no token present');
        setState(() {
          _hasBackendToken = false;
          _userRole = null;
          _isLoading = false;
        });
        debugPrint('[AUTHGATE] setState: hasBackendToken=false, userRole=null, isLoading=false');
        debugPrint('[AUTHGATE] authenticated=false');
      }
      // Clear work session provider when we lose backend token
      if (mounted) {
        final sessionProvider =
            Provider.of<WorkSessionProvider>(context, listen: false);
        sessionProvider.clear();
        debugPrint('[AUTHGATE] WorkSessionProvider cleared in _updateAuthState else');
        // Clear welcomed tasks for this session when we lose the token
        _welcomedTaskIds.clear();
      }
    }
    debugPrint('[AUTHGATE] _updateAuthState end');
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[AUTHGATE] build: _isLoading=$_isLoading, _hasBackendToken=$_hasBackendToken, _userRole=$_userRole, _user=$_user');
    if (_isLoading) {
      debugPrint('[AUTHGATE] building Loading');
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Check for restricted token (password change required)
    if (_isRestrictedToken) {
      debugPrint('[AUTHGATE] building ChangePasswordScreen (restricted token)');
      return ChangePasswordScreen();
    }

    // Check for backend authentication (JWT token) - REAL USERS
    if (_hasBackendToken && _userRole != null) {
      debugPrint('[AUTHGATE] building AppShell (backend authenticated)');
      if (_userRole == 'ADMIN') {
        return const AdminShell();
      } else if (_userRole == 'MANAGER') {
        return const ManagerShell();
      } else {
        return AppShell(
          showWelcomeBackModal: false, // Not used anymore
          unfinishedTask: null, // Not used anymore
          onContinueTask: () {}, // Not used anymore
          onChooseAnother: () {}, // Not used anymore
          onTutorialDismissed: null, // This is handled by the AppShell widget itself
        );
      }
    }


    // Not authenticated - show login
    debugPrint('[AUTHGATE] building LoginScreen');
    return const LoginScreen();
  }
}

// Welcome-back dialog shown when user logs in with an unfinished task.
class WelcomeBackDialog extends StatelessWidget {
  final WorkTask unfinishedTask;
  final WelcomeBackAction Function() onContinue;
  final WelcomeBackAction Function() onChooseAnother;

  const WelcomeBackDialog({
    super.key,
    required this.unfinishedTask,
    required this.onContinue,
    required this.onChooseAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.waving_hand,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Welcome back',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Body
            Text(
              'You have an unfinished task.',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 16),

            // Task info card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.assignment,
                        size: 16,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Current Task',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    unfinishedTask.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (unfinishedTask.category.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      unfinishedTask.category,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Question
            Text(
              'Would you like to continue this task?',
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 20),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      final action = onChooseAnother();
                      if (action == WelcomeBackAction.chooseAnother) {
                        Navigator.of(context).pop();
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Choose Another'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final action = onContinue();
                      if (action == WelcomeBackAction.continueTask) {
                        Navigator.of(context).pop(action);
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Continue Task'),
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