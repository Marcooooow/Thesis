import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  final String? profileImageUrl;
  final String name;
  final String? role;
  final double size;
  final String? presenceStatus; // 'online', 'dnd', 'break', 'meal', 'away', 'leave', 'offline'
  final bool showPresence;

  const UserAvatar({
    super.key,
    this.profileImageUrl,
    required this.name,
    this.role,
    this.size = 40,
    this.presenceStatus,
    this.showPresence = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final initials = _getInitials(name);

    Widget avatarContent;
    if (profileImageUrl != null && profileImageUrl!.isNotEmpty) {
      avatarContent = ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.network(
          profileImageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildInitialsAvatar(theme, isDark, initials);
          },
        ),
      );
    } else {
      avatarContent = _buildInitialsAvatar(theme, isDark, initials);
    }

    if (!showPresence || presenceStatus == null) {
      return SizedBox(width: size, height: size, child: avatarContent);
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatarContent,
          Positioned(
            right: -2,
            bottom: -2,
            child: _buildPresenceBadge(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialsAvatar(ThemeData theme, bool isDark, String initials) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.38,
        ),
      ),
    );
  }

  Widget _buildPresenceBadge(bool isDark) {
    final status = (presenceStatus ?? 'offline').toLowerCase();
    Color color;
    IconData? icon;

    switch (status) {
      case 'online':
        color = const Color(0xFF10B981); // Green
        break;
      case 'dnd':
        color = const Color(0xFFEF4444); // Red
        icon = Icons.remove;
        break;
      case 'break':
        color = const Color(0xFFF59E0B); // Amber/Orange
        icon = Icons.coffee_outlined;
        break;
      case 'meal':
        color = const Color(0xFF8B5CF6); // Purple
        icon = Icons.restaurant_outlined;
        break;
      case 'away':
        color = const Color(0xFFFBBF24); // Yellow
        icon = Icons.access_time;
        break;
      case 'leave':
        color = const Color(0xFF3B82F6); // Blue
        icon = Icons.calendar_today;
        break;
      case 'offline':
      default:
        color = const Color(0xFF6B7280); // Gray
        break;
    }

    final badgeSize = size * 0.35;

    return Container(
      width: badgeSize < 12 ? 12 : badgeSize,
      height: badgeSize < 12 ? 12 : badgeSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? const Color(0xFF1B1D24) : Colors.white,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(
              icon,
              size: badgeSize * 0.6,
              color: Colors.white,
            )
          : null,
    );
  }

  String _getInitials(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'U';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return trimmed[0].toUpperCase();
  }
}
