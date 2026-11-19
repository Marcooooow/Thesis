import 'package:flutter/material.dart';
import 'package:intellibreak/widgets/user_avatar.dart';

class ParticipantAvatar extends StatelessWidget {
  final String name;
  final String? role;
  final double size;
  final bool showOnline;
  final String? profileImageUrl;
  final String? presenceStatus;

  const ParticipantAvatar({
    super.key,
    required this.name,
    this.role,
    this.size = 40,
    this.showOnline = false,
    this.profileImageUrl,
    this.presenceStatus,
  });

  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      profileImageUrl: profileImageUrl,
      name: name,
      role: role,
      size: size,
      presenceStatus: presenceStatus ?? (showOnline ? 'online' : 'offline'),
      showPresence: showOnline || presenceStatus != null,
    );
  }
}
