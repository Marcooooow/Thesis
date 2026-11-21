import 'package:flutter/material.dart';
import 'package:intellibreak/features/notifications/notification_navigator.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/providers/notification_provider.dart';
import 'package:intellibreak/features/notifications/models/notification_model.dart';
import 'package:intellibreak/widgets/state_display.dart';

class NotificationCenterScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const NotificationCenterScreen({super.key, this.onBack});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedCategory = 'ALL';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().loadNotifications();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  List<NotificationModel> _filterNotifications(List<NotificationModel> notifications, int tabIndex) {
    // Tab 0: All, Tab 1: Unread, Tab 2: Read
    List<NotificationModel> filtered = notifications.where((n) {
      if (tabIndex == 1) return !n.isRead;
      if (tabIndex == 2) return n.isRead;
      return true;
    }).toList();

    // Category filter
    if (_selectedCategory != 'ALL') {
      filtered = filtered.where((n) {
        if (_selectedCategory == 'TEAM') return n.type.contains('TEAM');
        if (_selectedCategory == 'BREAK') return n.type.contains('BREAK') || n.type.contains('WORK');
        if (_selectedCategory == 'WELLBEING') return n.type.contains('WELLBEING');
        if (_selectedCategory == 'ADMIN') return n.type.contains('ADMIN') || n.type.contains('APPROVAL');
        return true;
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Page Header
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                if (widget.onBack != null) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onBack,
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 8),
                ],
                const Text(
                  'Notification Center',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Consumer<NotificationProvider>(
                  builder: (context, provider, _) {
                    if (provider.unreadCount == 0) return const SizedBox.shrink();
                    return TextButton.icon(
                      onPressed: () => provider.markAllAsRead(),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('Mark all read'),
                    );
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => context.read<NotificationProvider>().refresh(),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          // TabBar
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Unread'),
              Tab(text: 'Read'),
            ],
          ),
          const Divider(height: 1),
          // Category Filter Chips
          SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCategoryChip('ALL', 'All'),
                  const SizedBox(width: 8),
                  _buildCategoryChip('TEAM', 'Team & Invitations'),
                  const SizedBox(width: 8),
                  _buildCategoryChip('BREAK', 'Breaks & Work'),
                  const SizedBox(width: 8),
                  _buildCategoryChip('WELLBEING', 'Wellbeing'),
                  const SizedBox(width: 8),
                  _buildCategoryChip('ADMIN', 'Admin & System'),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Content Area with StateDisplay inside Expanded
          Expanded(
            child: Consumer<NotificationProvider>(
              builder: (context, provider, _) {
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTabContent(provider, 0),
                    _buildTabContent(provider, 1),
                    _buildTabContent(provider, 2),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String code, String label) {
    final isSelected = _selectedCategory == code;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedCategory = code;
        });
      },
    );
  }

  Widget _buildTabContent(NotificationProvider provider, int tabIndex) {
    final items = _filterNotifications(provider.notifications, tabIndex);

    return StateDisplay(
      isLoading: provider.isLoading && provider.notifications.isEmpty,
      errorMessage: provider.error,
      isEmpty: items.isEmpty,
      emptyMessage: 'No notifications in this view.',
      emptyIcon: Icons.notifications_none_outlined,
      onRetry: () => provider.refresh(),
      content: RefreshIndicator(
        onRefresh: () => provider.refresh(),
        child: ListView.separated(
          itemCount: items.length,
          shrinkWrap: false,
          physics: const AlwaysScrollableScrollPhysics(),
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final notification = items[index];
            return ListTile(
              tileColor: !notification.isRead ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.04) : null,
              leading: CircleAvatar(
                backgroundColor: _getIconColor(notification.type),
                child: Icon(
                  _getNotificationIcon(notification.type),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      notification.title,
                      style: TextStyle(
                        fontWeight: !notification.isRead ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!notification.isRead)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(notification.message),
                  const SizedBox(height: 6),
                  Text(
                    _formatTime(notification.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: !notification.isRead
                  ? IconButton(
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      tooltip: 'Mark as read',
                      onPressed: () => provider.markAsRead(notification.id),
                    )
                  : null,
              onTap: () {
                if (!notification.isRead) {
                  provider.markAsRead(notification.id);
                }
                // Leave the notification center and open the related screen.
                if (NotificationNavigator.open(notification) && widget.onBack == null && Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
            );
          },
        ),
      ),
    );
  }

  Color _getIconColor(String type) {
    if (type.contains('TEAM') || type.contains('INVITATION')) return Colors.indigo;
    if (type.contains('BREAK') || type.contains('WORK')) return Colors.teal;
    if (type.contains('WELLBEING')) return Colors.orange;
    if (type.contains('ADMIN') || type.contains('APPROVAL')) return Colors.deepPurple;
    return Colors.blueGrey;
  }

  IconData _getNotificationIcon(String type) {
    if (type.contains('TEAM') || type.contains('INVITATION')) return Icons.group;
    if (type.contains('BREAK') || type.contains('WORK')) return Icons.timer;
    if (type.contains('WELLBEING')) return Icons.favorite;
    if (type.contains('ADMIN') || type.contains('APPROVAL')) return Icons.admin_panel_settings;
    return Icons.notifications;
  }
}
