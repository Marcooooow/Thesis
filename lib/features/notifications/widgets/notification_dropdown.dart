import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/features/notifications/models/notification_model.dart';
import 'package:intellibreak/features/notifications/screens/notification_center_screen.dart';
import 'package:intellibreak/providers/notification_provider.dart';
import 'package:intellibreak/providers/team_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationDropdown extends StatefulWidget {
  final bool isDark;
  final bool isHighContrast;
  final VoidCallback? onOpenNotificationCenter;

  const NotificationDropdown({
    super.key,
    required this.isDark,
    required this.isHighContrast,
    this.onOpenNotificationCenter,
  });

  @override
  State<NotificationDropdown> createState() => _NotificationDropdownState();
}

class _NotificationDropdownState extends State<NotificationDropdown> {
  @override
  void initState() {
    super.initState();
    // Load notifications when dropdown opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<NotificationProvider>();
      if (provider.notifications.isEmpty && !provider.isLoading) {
        provider.loadNotifications();
      }
    });
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return dateTime.toLocal().toString().split(' ')[0];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, provider, _) {
        return Container(
          width: 380,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: widget.isDark
                ? (widget.isHighContrast
                      ? const Color(0xFF0D0D0D)
                      : const Color(0xFF151A21))
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Notifications',
                        style: TextStyle(
                          color: widget.isDark
                              ? (widget.isHighContrast
                                    ? Colors.white
                                    : const Color(0xFFE8EBEF))
                              : Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (provider.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${provider.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: widget.isDark
                      ? (widget.isHighContrast
                            ? Colors.white.withValues(alpha: 0.1)
                            : const Color(0xFF262D37))
                      : const Color(0xFFE2E6EB),
                ),
                // Content
                provider.isLoading
                    ? _buildLoadingState()
                    : provider.error != null
                    ? _buildErrorState(provider, context)
                    : provider.notifications.isEmpty
                    ? _buildEmptyState()
                    : _buildNotificationsList(provider),
                Divider(
                  height: 1,
                  color: widget.isDark
                      ? (widget.isHighContrast
                            ? Colors.white.withValues(alpha: 0.1)
                            : const Color(0xFF262D37))
                      : const Color(0xFFE2E6EB),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: TextButton(
                    onPressed: () {
                      if (widget.onOpenNotificationCenter != null) {
                        widget.onOpenNotificationCenter!();
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NotificationCenterScreen(),
                          ),
                        );
                      }
                    },
                    child: const Text('Open Notification Center'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return SizedBox(
      height: 240,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(NotificationProvider provider, BuildContext context) {
    return SizedBox(
      height: 240,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                color: widget.isDark
                    ? (widget.isHighContrast
                          ? Colors.white.withValues(alpha: 0.5)
                          : const Color(0xFF9AA3AF))
                    : Colors.grey,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                'Failed to load notifications',
                style: TextStyle(
                  color: widget.isDark
                      ? (widget.isHighContrast
                            ? Colors.white
                            : const Color(0xFFE8EBEF))
                      : Colors.black,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  provider.refresh();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 240,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.notifications_off_outlined,
                color: widget.isDark
                    ? (widget.isHighContrast
                          ? Colors.white.withValues(alpha: 0.5)
                          : const Color(0xFF9AA3AF))
                    : Colors.grey,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                "You're all caught up.",
                style: TextStyle(
                  color: widget.isDark
                      ? (widget.isHighContrast
                            ? Colors.white
                            : const Color(0xFFE8EBEF))
                      : Colors.black,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationsList(NotificationProvider provider) {
    return SizedBox(
      height: 240,
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: provider.notifications.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: widget.isDark
              ? (widget.isHighContrast
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFF262D37))
              : const Color(0xFFF0F0F0),
        ),
        itemBuilder: (context, index) {
          final notification = provider.notifications[index];
          return _buildNotificationItem(notification, provider);
        },
      ),
    );
  }

  Widget _buildNotificationItem(
    NotificationModel notification,
    NotificationProvider provider,
  ) {
    final isTeamInvitation = notification.type == 'TEAM_INVITATION';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isTeamInvitation
            ? null
            : () {
                if (!notification.isRead) {
                  provider.markAsRead(notification.id);
                }
              },
        child: Container(
          color: !notification.isRead
              ? (widget.isDark
                    ? (widget.isHighContrast
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFF2A2C34))
                    : const Color(0xFFF5F6F8))
              : Colors.transparent,
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      notification.title,
                      style: TextStyle(
                        color: widget.isDark
                            ? (widget.isHighContrast
                                  ? Colors.white
                                  : const Color(0xFFE8EBEF))
                            : Colors.black,
                        fontSize: 14,
                        fontWeight: !notification.isRead
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!notification.isRead)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F766E),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                notification.message,
                style: TextStyle(
                  color: widget.isDark
                      ? (widget.isHighContrast
                            ? Colors.white.withValues(alpha: 0.7)
                            : const Color(0xFF9AA3AF))
                      : Colors.grey.shade600,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _formatTime(notification.createdAt),
                style: TextStyle(
                  color: widget.isDark
                      ? (widget.isHighContrast
                            ? Colors.white.withValues(alpha: 0.5)
                            : const Color(0xFF9AA3AF))
                      : Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
              // Action buttons for team invitations
              if (isTeamInvitation && !(notification.isActioned)) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _declineInvitation(context, notification, provider),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _acceptInvitation(context, notification, provider),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Accept'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Accept a team invitation.
  Future<void> _acceptInvitation(
    BuildContext context,
    NotificationModel notification,
    NotificationProvider provider,
  ) async {
    final invitationId = notification.relatedEntityId;
    if (invitationId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid invitation')));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    if (token == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication required')),
        );
      }
      return;
    }

    if (!context.mounted) return;

    final teamProvider = context.read<TeamProvider>();
    final success = await teamProvider.acceptInvitation(invitationId, token);

    if (!context.mounted) return;

    if (success) {
      // Update local notification state immediately so buttons disappear
      final updatedNotification = notification.copyWith(isActioned: true);
      final idx = provider.notifications.indexWhere(
        (n) => n.id == notification.id,
      );
      if (idx != -1) {
        provider.notifications[idx] = updatedNotification;
      }
      // Also refresh from backend to keep history consistent
      await provider.refresh();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invitation accepted! You are now a team member.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(teamProvider.error ?? 'Failed to accept invitation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Decline a team invitation.
  Future<void> _declineInvitation(
    BuildContext context,
    NotificationModel notification,
    NotificationProvider provider,
  ) async {
    final invitationId = notification.relatedEntityId;
    if (invitationId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid invitation')));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    if (token == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication required')),
        );
      }
      return;
    }

    if (!context.mounted) return;

    final teamProvider = context.read<TeamProvider>();

    // We need the teamId to decline. This should be passed via notification or we load it from provider.
    // For now, assume we have the current team context.
    final teamId = teamProvider.currentTeam?.id;
    if (teamId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Team context required')));
      return;
    }

    final success = await teamProvider.declineInvitation(
      invitationId,
      token,
      teamId,
    );

    if (!context.mounted) return;

    if (success) {
      // Update local notification state immediately so buttons disappear
      final updatedNotification = notification.copyWith(isActioned: true);
      final idx = provider.notifications.indexWhere(
        (n) => n.id == notification.id,
      );
      if (idx != -1) {
        provider.notifications[idx] = updatedNotification;
      }
      // Refresh from backend to keep history consistent
      await provider.refresh();

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invitation declined.')));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(teamProvider.error ?? 'Failed to decline invitation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
