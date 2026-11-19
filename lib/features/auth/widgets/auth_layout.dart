import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

/// Layout for authentication screens using responsive design.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    required this.desktop,
    required this.tablet,
    required this.mobile,
    super.key,
  });

  final Widget desktop;
  final Widget tablet;
  final Widget mobile;

  @override
  Widget build(BuildContext context) {
    return DesignSystem.responsiveLayout(
      desktop: desktop,
      tablet: tablet,
      mobile: mobile,
    );
  }
}
