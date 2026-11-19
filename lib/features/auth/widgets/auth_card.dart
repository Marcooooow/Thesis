import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

/// A card container for authentication forms, using the design system.
class AuthCard extends StatelessWidget {
  const AuthCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DesignSystem.authCard(context: context, child: child);
  }
}
