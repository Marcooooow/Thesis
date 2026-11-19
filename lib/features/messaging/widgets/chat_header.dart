import 'package:flutter/material.dart';
import 'package:intellibreak/features/messaging/widgets/participant_avatar.dart';

class ChatHeader extends StatelessWidget implements PreferredSizeWidget {
  final String participantName;
  final String participantRole;
  final VoidCallback? onBackPressed;
  final VoidCallback? onMarkRead;

  const ChatHeader({
    super.key,
    required this.participantName,
    required this.participantRole,
    this.onBackPressed,
    this.onMarkRead,
  });

  @override
  Size get preferredSize => const Size.fromHeight(70);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedRole = participantRole.isNotEmpty
        ? participantRole[0].toUpperCase() + participantRole.substring(1).toLowerCase()
        : 'Employee';

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (onBackPressed != null) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: onBackPressed,
              tooltip: 'Back',
            ),
            const SizedBox(width: 8),
          ],
          ParticipantAvatar(
            name: participantName,
            role: participantRole,
            size: 42,
            showOnline: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participantName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      formattedRole,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      ' • IntelliBreak Workspace',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onMarkRead != null)
            IconButton(
              icon: const Icon(Icons.mark_chat_read_outlined),
              tooltip: 'Mark as read',
              onPressed: onMarkRead,
            ),
        ],
      ),
    );
  }
}
