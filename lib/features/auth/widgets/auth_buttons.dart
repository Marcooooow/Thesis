import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

/// A container for primary and secondary buttons in authentication screens.
class AuthButtons extends StatelessWidget {
  const AuthButtons({
    required this.primaryLabel,
    required this.primaryOnPressed,
    this.secondaryLabel,
    this.secondaryOnPressed,
    this.primaryIsLoading = false,
    this.secondaryIsLoading = false,
    super.key,
  });

  final String primaryLabel;
  final VoidCallback primaryOnPressed;
  final String? secondaryLabel;
  final VoidCallback? secondaryOnPressed;
  final bool primaryIsLoading;
  final bool secondaryIsLoading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DesignSystem.primaryButton(
            context: context,
            label: primaryLabel,
            onPressed: primaryOnPressed,
            isLoading: primaryIsLoading,
          ),
        ),
        if (secondaryLabel != null && secondaryOnPressed != null) ...[
          const SizedBox(width: DesignSystem.spacingS),
          Expanded(
            child: DesignSystem.secondaryButton(
              context: context,
              label: secondaryLabel!,
              onPressed: secondaryOnPressed!,
              isLoading: secondaryIsLoading,
            ),
          ),
        ],
      ],
    );
  }
}