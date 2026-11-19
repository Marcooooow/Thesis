import 'package:flutter/material.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:provider/provider.dart';

/// Universal scaffold for admin pages providing consistent layout,
/// Material hierarchy, and responsive design.
class AdminPageScaffold extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showBackButton;

  const AdminPageScaffold({
    super.key,
    required this.title,
    this.icon,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(context)
        .isHighContrast;
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;

    return Material(
      color: isDark
          ? (isHighContrast ? const Color(0xFF0D0D0D) : const Color(0xFF1A1A1A))
          : Colors.white,
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isDesktop ? 24 : 16,
                  isDesktop ? 24 : 16,
                  isDesktop ? 24 : 16,
                  isDesktop ? 16 : 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Page header with optional back button
                    Row(
                      children: [
                        if (showBackButton)
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.arrow_back,
                              color: isDark
                                  ? (isHighContrast
                                        ? Colors.white
                                        : Colors.white)
                                  : Colors.black,
                            ),
                          ),
                        if (icon != null) ...[
                          Icon(
                            icon!,
                            size: 28,
                            color: isDark
                                ? (isHighContrast ? Colors.white : Colors.white)
                                : Colors.black,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: isDesktop ? 24 : 20,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? (isHighContrast
                                        ? Colors.white
                                        : Colors.white)
                                  : Colors.black,
                            ),
                          ),
                        ),
                        if (actions?.isNotEmpty ?? false) ...actions!,
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: true,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 16),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
