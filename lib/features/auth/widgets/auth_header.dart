import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

/// Header for authentication screens showing title and subtitle.
class AuthHeader extends StatelessWidget {
  const AuthHeader({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DesignSystem.authHeader(
      context: context,
      title: title,
      subtitle: subtitle,
    );
  }
}
