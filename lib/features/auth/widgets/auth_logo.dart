import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

/// Displays the IntelliBreak bolt logo.
class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(DesignSystem.radiusXL),
      ),
      child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 36),
    );
  }
}
