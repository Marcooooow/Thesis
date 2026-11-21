import 'package:flutter/material.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:intellibreak/core/utils/responsive_layout.dart';
import 'package:provider/provider.dart';

enum SemanticColor {
  primary,
  secondary,
  success,
  warning,
  error,
  info,
  surface,
  background,
  onSurface,
  onSurfaceVariant,
  // Shift Controller semantic state colors
  shiftStart,    // Fresh Green
  shiftBreak1,   // Soft Teal
  shiftBreak2,   // Ocean Blue
  shiftLunch,    // Warm Amber
  shiftMeeting,  // Soft Purple
  shiftCoachBreak, // Soft Rose
  shiftEnd,      // Sunset Coral
}

/// IntelliBreak Design System - Reusable tokens and components
/// Enhanced with FlareLine-inspired visual sophistication

class DesignSystem {
  // ============================
  // FLARELINE-INSPIRED COLOR SYSTEM
  // ============================

  static Color getSemanticColor(BuildContext context, SemanticColor type) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    // FlareLine-inspired dark theme colors
    const Color flarelineCardBackground = Color(0xFF182029);
    const Color flarelinePrimaryText = Color(0xFFE8EBEF);
    const Color flarelineSecondaryText = Color(0xFF9AA3AF);
    final Color flarelineAccent = theme.colorScheme.primary;

    if (isDark) {
      switch (type) {
        case SemanticColor.primary:
          return flarelineAccent;
        case SemanticColor.secondary:
          return flarelineAccent.withValues(alpha: 0.8);
        case SemanticColor.success:
          return Colors.greenAccent.withValues(alpha: 0.8);
        case SemanticColor.warning:
          return Colors.orangeAccent.withValues(alpha: 0.8);
        case SemanticColor.error:
          return Colors.redAccent.withValues(alpha: 0.8);
        case SemanticColor.info:
          return Colors.blueAccent.withValues(alpha: 0.8);
        case SemanticColor.shiftStart:
          return Colors.greenAccent.withValues(alpha: 0.9);
        case SemanticColor.shiftBreak1:
          return Colors.tealAccent.withValues(alpha: 0.9);
        case SemanticColor.shiftBreak2:
          return Colors.blueAccent.withValues(alpha: 0.9);
        case SemanticColor.shiftLunch:
          return const Color(0xFFDAA520);
        case SemanticColor.shiftMeeting:
          return Colors.purpleAccent.withValues(alpha: 0.9);
        case SemanticColor.shiftCoachBreak:
          return const Color(0xFFD98FA3);
        case SemanticColor.shiftEnd:
          return Colors.redAccent.withValues(alpha: 0.9);
        case SemanticColor.surface:
          return flarelineCardBackground;
        case SemanticColor.background:
          return flarelineCardBackground;
        case SemanticColor.onSurface:
          return isHighContrast
              ? Colors.white
              : flarelinePrimaryText.withValues(alpha: 0.9);
        case SemanticColor.onSurfaceVariant:
          return isHighContrast
              ? Colors.white.withValues(alpha: 0.7)
              : flarelineSecondaryText;
      }
    } else {
      // Light theme - keep existing but refine
      switch (type) {
        case SemanticColor.primary:
          return theme.colorScheme.primary;
        case SemanticColor.secondary:
          return theme.colorScheme.secondary;
        case SemanticColor.success:
          return Colors.green[600]!;
        case SemanticColor.warning:
          return Colors.orange[600]!;
        case SemanticColor.error:
          return Colors.red[600]!;
        case SemanticColor.info:
          return Colors.blue[600]!;
        case SemanticColor.shiftStart:
          return const Color(0xFF2ECC71);
        case SemanticColor.shiftBreak1:
          return const Color(0xFF20B2AA);
        case SemanticColor.shiftBreak2:
          return const Color(0xFF4682B4);
        case SemanticColor.shiftLunch:
          return const Color(0xFFDAA520);
        case SemanticColor.shiftMeeting:
          return const Color(0xFF9370DB);
        case SemanticColor.shiftCoachBreak:
          return const Color(0xFFD98FA3);
        case SemanticColor.shiftEnd:
          return const Color(0xFFE07A5F);
        case SemanticColor.surface:
          return theme.colorScheme.surface;
        case SemanticColor.onSurface:
          return theme.colorScheme.onSurface;
        case SemanticColor.onSurfaceVariant:
          return theme.colorScheme.onSurface.withValues(alpha: 0.6);
        default:
          return theme.colorScheme.onSurface;
      }
    }
  }

  // ============================
  // REFINED SPACING SYSTEM (4px grid)
  // ============================
  static const double spacingXXS = 2.0; // Extra extra small
  static const double spacingXS = 4.0; // Extra small
  static const double spacingS = 8.0; // Small
  static const double spacingM = 12.0; // Medium
  static const double spacingL = 16.0; // Large
  static const double spacingXL = 20.0; // Extra large
  static const double spacingXXL = 24.0; // Double extra large
  static const double spacingXXXL = 32.0; // Triple extra large

  // ============================
  // REFINED BORDER RADIUS
  // ============================
  static const double radiusXXS = 2.0;
  static const double radiusXS = 4.0;
  static const double radiusS = 6.0;
  static const double radiusM = 8.0;
  static const double radiusL = 12.0;
  static const double radiusXL = 16.0;
  static const double radiusXXL = 20.0;

  // ============================
  // ELEVATED TYPOGRAPHY SYSTEM
  // ============================
  static TextStyle body(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return TextStyle(
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: _getTextColor(context, isDark, isHighContrast, 0.9),
    );
  }

  static TextStyle bodyLarge(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return TextStyle(
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: _getTextColor(context, isDark, isHighContrast, 0.9),
    );
  }

  static TextStyle label(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: _getTextColor(context, isDark, isHighContrast, 0.8),
    );
  }

  static TextStyle labelLarge(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: _getTextColor(context, isDark, isHighContrast, 0.8),
    );
  }

  static TextStyle labelMedium(BuildContext context) => labelLarge(context);

  static TextStyle caption(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: _getTextColor(context, isDark, isHighContrast, 0.6),
    );
  }

  static TextStyle data(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: _getTextColor(context, isDark, isHighContrast, 0.9),
    );
  }

  static TextStyle dataLarge(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: _getTextColor(context, isDark, isHighContrast, 0.9),
    );
  }

  static TextStyle title(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: _getTextColor(context, isDark, isHighContrast, 0.9),
    );
  }

  static TextStyle titleLarge(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: _getTextColor(context, isDark, isHighContrast, 1.0),
    );
  }

  static TextStyle titleXL(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: _getTextColor(context, isDark, isHighContrast, 1.0),
    );
  }

  static TextStyle titleXXL(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: _getTextColor(context, isDark, isHighContrast, 1.0),
    );
  }

  static TextStyle titleXXXL(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: _getTextColor(context, isDark, isHighContrast, 1.0),
    );
  }

  /// Formats a [TimeOfDay] according to the given format ('12h' or '24h').
  /// Returns a string suitable for display to the user.
  static String formatTimeOfDay(TimeOfDay time, String format) {
    if (format == '12h') {
      final hour = time.hour % 12;
      final displayHour = hour == 0 ? 12 : hour;
      final period = time.hour >= 12 ? 'PM' : 'AM';
      return '$displayHour:${time.minute.toString().padLeft(2, '0')} $period';
    } else {
      // 24-hour format
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  // Keep backward compatibility
  static TextStyle textXS(BuildContext context) => caption(context);
  static TextStyle textS(BuildContext context) => body(context);
  static TextStyle textM(BuildContext context) => labelLarge(context);
  static TextStyle textL(BuildContext context) => title(context);
  static TextStyle textXL(BuildContext context) => titleLarge(context);
  static TextStyle textXXL(BuildContext context) => titleXL(context);
  static TextStyle textXXXL(BuildContext context) => titleXXL(context);

  static Color _getTextColor(
    BuildContext context,
    bool isDark,
    bool isHighContrast,
    double opacity,
  ) {
    if (isHighContrast) {
      return isDark
          ? Colors.white.withValues(alpha: opacity)
          : Colors.black.withValues(alpha: opacity);
    }
    final ThemeData theme = Theme.of(context);
    return isDark
        ? (theme.colorScheme.brightness == Brightness.dark
              ? Colors.white.withValues(alpha: opacity)
              : const Color(0xFF9AA3AF).withValues(alpha: opacity))
        : (theme.colorScheme.brightness == Brightness.light
              ? const Color(0xFF111827).withValues(alpha: opacity)
              : const Color(0xFF5B6472).withValues(alpha: opacity));
  }

  // ============================
  // ANIMATION SYSTEM
  // ============================
  static const Duration durationFast = Duration(milliseconds: 80);
  static const Duration durationModerate = Duration(milliseconds: 150);
  static const Duration durationSlow = Duration(milliseconds: 250);

  static const Curve easeInOut = Cubic(0.4, 0, 0.2, 1);
  static const Curve easeOut = Cubic(0.0, 0, 0.2, 1);
  static const Curve easeIn = Cubic(0.4, 0, 1, 1);
  static const Curve easeInOutBack = Cubic(0.37, 0.01, 0.28, 1.01);

  // ============================
  // REUSABLE COMPONENTS
  // ============================

  /// Clean, modern card without excessive padding or elevation
  static Widget dashboardCard({
    required BuildContext context,
    required Widget child,
    double padding = 16.0,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(8)),
    Color? backgroundColor,
    bool withBorder = true,
  }) {
    final Color bgColor =
        backgroundColor ?? Theme.of(context).colorScheme.surface;
    final Color dividerColor = withBorder
        ? (Theme.of(context).dividerTheme.color ??
              Theme.of(context).colorScheme.outline)
        : Colors.transparent;
    final double dividerThickness =
        Theme.of(context).dividerTheme.thickness ?? 1.0;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
        border: Border.all(color: dividerColor, width: dividerThickness),
      ),
      padding: EdgeInsets.all(padding),
      child: child,
    );
  }

  /// Elevated card with subtle shadow for emphasis
  static Widget elevatedCard({
    required BuildContext context,
    required Widget child,
    Color? backgroundColor,
    double padding = 16.0,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(8)),
    bool withBorder = true,
  }) {
    final Color bgColor =
        backgroundColor ?? Theme.of(context).colorScheme.surface;
    final Color dividerColor = withBorder
        ? (Theme.of(context).dividerTheme.color ??
              Theme.of(context).colorScheme.outline)
        : Colors.transparent;
    final double dividerThickness =
        Theme.of(context).dividerTheme.thickness ?? 1.0;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
        border: Border.all(color: dividerColor, width: dividerThickness),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.all(padding),
      child: child,
    );
  }

  static Widget premiumCard({
    required BuildContext context,
    required Widget child,
    double padding = 16.0,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12)),
    Color? backgroundColor,
    bool withBorder = true,
  }) {
    final Color bgColor =
        backgroundColor ?? Theme.of(context).colorScheme.surface;
    final Color dividerColor = withBorder
        ? (Theme.of(context).dividerTheme.color ??
              Theme.of(context).colorScheme.outline)
        : Colors.transparent;
    final double dividerThickness =
        Theme.of(context).dividerTheme.thickness ?? 1.0;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
        border: Border.all(color: dividerColor, width: dividerThickness),
      ),
      padding: EdgeInsets.all(padding),
      child: child,
    );
  }

  static Widget sectionHeader(
    BuildContext context,
    String title,
    IconData icon, {
    String? subTitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(spacingXS),
              decoration: BoxDecoration(
                color: getSemanticColor(
                  context,
                  SemanticColor.primary,
                ).withValues(alpha: 0.1),
                borderRadius: BorderRadius.all(Radius.circular(radiusS)),
              ),
              child: Icon(
                icon,
                size: 20,
                color: getSemanticColor(context, SemanticColor.primary),
              ),
            ),
            const SizedBox(width: spacingS),
            Flexible(
              fit: FlexFit.loose,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: titleLarge(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: getSemanticColor(context, SemanticColor.onSurface),
                    ),
                  ),
                  if (subTitle != null && subTitle.isNotEmpty) ...[
                    const SizedBox(height: spacingXXS),
                    Text(
                      subTitle,
                      style: caption(context).copyWith(
                        color: getSemanticColor(
                          context,
                          SemanticColor.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (subTitle != null && subTitle.isNotEmpty) ...[
          const SizedBox(height: spacingXS),
          Divider(
            color: getSemanticColor(
              context,
              SemanticColor.onSurfaceVariant,
            ).withValues(alpha: 0.2),
            height: 1,
          ),
        ] else ...[
          const SizedBox(height: spacingS),
          Divider(
            color: getSemanticColor(
              context,
              SemanticColor.onSurfaceVariant,
            ).withValues(alpha: 0.1),
            height: 1,
          ),
        ],
      ],
    );
  }

  /// Enhanced stat card for dashboards
  static Widget statCard({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    String? description,
    double? iconSize,
    bool showProgress = false,
    double progress = 0.0,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? getSemanticColor(
                context,
                SemanticColor.background,
              ).withValues(alpha: 0.8)
            : getSemanticColor(context, SemanticColor.surface),
        borderRadius: BorderRadius.circular(radiusL),
        border: Border.all(
          color: isDark
              ? getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ).withValues(alpha: 0.2)
              : getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ).withValues(alpha: 0.1),
        ),
      ),
      padding: EdgeInsets.all(spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + Label
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(spacingXS),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.all(Radius.circular(radiusM)),
                ),
                child: Icon(icon, size: iconSize ?? 20, color: color),
              ),
              const SizedBox(width: spacingS),
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  label,
                  style: labelLarge(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? getSemanticColor(
                            context,
                            SemanticColor.onSurface,
                          ).withValues(alpha: 0.8)
                        : getSemanticColor(
                            context,
                            SemanticColor.onSurface,
                          ).withValues(alpha: 0.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: spacingXS),
          // Value
          Text(
            value,
            style: titleLarge(context).copyWith(
              fontWeight: FontWeight.bold,
              color: isDark
                  ? getSemanticColor(context, SemanticColor.onSurface)
                  : getSemanticColor(context, SemanticColor.onSurface),
            ),
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: spacingXS),
            Text(
              description,
              style: caption(context).copyWith(
                color: isDark
                    ? getSemanticColor(
                        context,
                        SemanticColor.onSurfaceVariant,
                      ).withValues(alpha: 0.6)
                    : getSemanticColor(
                        context,
                        SemanticColor.onSurfaceVariant,
                      ).withValues(alpha: 0.6),
              ),
            ),
          ],
          if (showProgress) ...[
            const SizedBox(height: spacingS),
            SizedBox(
              height: 4,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(
                        width: constraints.maxWidth,
                        height: 4,
                        decoration: BoxDecoration(
                          color: getSemanticColor(
                            context,
                            SemanticColor.onSurfaceVariant,
                          ).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Container(
                        width: constraints.maxWidth * progress,
                        height: 4,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Stat card with progress indicator (for metrics like focus rate)
  static Widget statCardWithProgress({
    required BuildContext context,
    required String label,
    required String value,
    required double progress,
    required IconData icon,
    required Color color,
    String? description,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radiusL),
        border: Border.all(
          color: isDark
              ? getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ).withValues(alpha: 0.2)
              : getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ).withValues(alpha: 0.1),
        ),
      ),
      padding: EdgeInsets.all(spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with label and progress
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Label and value
              Flexible(
                fit: FlexFit.loose,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: labelLarge(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? getSemanticColor(
                                context,
                                SemanticColor.onSurface,
                              ).withValues(alpha: 0.8)
                            : getSemanticColor(
                                context,
                                SemanticColor.onSurface,
                              ).withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: spacingXS),
                    Text(
                      value,
                      style: titleLarge(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? getSemanticColor(context, SemanticColor.onSurface)
                            : getSemanticColor(
                                context,
                                SemanticColor.onSurface,
                              ),
                      ),
                    ),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: spacingXS),
                      Text(
                        description,
                        style: caption(context).copyWith(
                          color: isDark
                              ? getSemanticColor(
                                  context,
                                  SemanticColor.onSurfaceVariant,
                                ).withValues(alpha: 0.6)
                              : getSemanticColor(
                                  context,
                                  SemanticColor.onSurfaceVariant,
                                ).withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Progress indicator
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background circle
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.1),
                      ),
                    ),
                    // Progress arc
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 8,
                        color: color,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                    // Center value
                    Center(
                      child: Text(
                        '${(progress * 100).roundToDouble()}%',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Compact stat card for dashboards
  static Widget statCardCompact({
    required BuildContext context,
    required String labelText,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.all(Radius.circular(8)),
        border: Border.all(
          color:
              Theme.of(context).dividerTheme.color ??
              Theme.of(context).colorScheme.outline,
          width: Theme.of(context).dividerTheme.thickness ?? 1.0,
        ),
      ),
      padding: EdgeInsets.all(spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + Label (accessibility)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(spacingXS),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.all(Radius.circular(radiusS)),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: spacingS),
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  labelText,
                  style: DesignSystem.label(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? (isHighContrast
                              ? Colors.white.withValues(alpha: 0.8)
                              : Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.8))
                        : Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: spacingXS),
          Text(
            value,
            style: title(context).copyWith(
              fontWeight: FontWeight.bold,
              color: isDark
                  ? (isHighContrast
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface)
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ============================
  // RESPONSIVE LAYOUT HELPERS
  // ============================
  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1100;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600 &&
      MediaQuery.of(context).size.width < 1100;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  static bool isCompactDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1100 &&
      MediaQuery.of(context).size.width < 1400;

  static bool isStandardDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1400 &&
      MediaQuery.of(context).size.width < 1920;

  static bool isWideDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1920;

  /// Get appropriate sidebar width based on screen size
  static double getSidebarWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1920) return 280; // Large desktop
    if (width >= 1400) return 260; // Standard desktop
    if (width >= 1100) return 240; // Compact desktop/laptop
    if (width >= 600) return 200; // Tablet
    return 0; // Mobile (handled via drawer)
  }

  /// Responsive layout helper for authentication screens.
  static Widget responsiveLayout({
    required Widget desktop,
    required Widget tablet,
    required Widget mobile,
  }) {
    return ResponsiveLayout(desktop: desktop, tablet: tablet, mobile: mobile);
  }

  // ============================
  // METRIC COMPONENTS
  // ============================

  /// Compact metric indicator for dashboards
  static Widget metricIndicatorCompact({
    required BuildContext context,
    required String label,
    required String value,
    double progress = 0.0, // 0.0 to 1.0
    int dotCount = 8,
    double dotSize = 4.0,
    double dotSpacing = 2.0,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;
    final ThemeController themeController = Provider.of<ThemeController>(
      context,
      listen: false,
    );
    final Color accentColor = themeController.accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label and value
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: title(context).copyWith(
                fontWeight: FontWeight.w600,
                color: isDark
                    ? (isHighContrast
                          ? Colors.white.withValues(alpha: 0.8)
                          : Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.8))
                    : Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.8),
              ),
            ),
            Text(
              value,
              style: titleLarge(context).copyWith(
                color: isDark
                    ? (isHighContrast
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Dot progress indicator
        SizedBox(
          height: dotSize,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: dotCount,
            itemBuilder: (context, index) {
              final bool isFilled = index < (progress * dotCount).floor();
              return Container(
                width: dotSize,
                margin: EdgeInsets.only(
                  right: index < dotCount - 1 ? dotSpacing : 0,
                ),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled
                      ? accentColor.withValues(alpha: 0.3)
                      : (Theme.of(context).dividerTheme.color ??
                                Theme.of(context).colorScheme.outline)
                            .withValues(alpha: 0.3),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Horizontal metric layout for dashboards
  static Widget metricRowHorizontal({
    required BuildContext context,
    required List<Widget> metrics,
  }) {
    return Row(
      children: metrics.map((metric) => Expanded(child: metric)).toList(),
    );
  }

  // ============================
  // BUTTON COMPONENTS
  // ============================

  /// Primary button for main actions
  static Widget primaryButton({
    required BuildContext context,
    required String label,
    required VoidCallback onPressed,
    bool isLoading = false,
    double width = double.infinity,
    double height = 52.0,
    IconData? icon,
    bool withElevation = true,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: isDark
              ? (isHighContrast ? Colors.white : Colors.white)
              : Theme.of(context).colorScheme.onSurface,
          elevation: withElevation ? 0 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusM),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }

  /// Secondary button for secondary actions
  static Widget secondaryButton({
    required BuildContext context,
    required String label,
    required VoidCallback onPressed,
    bool isLoading = false,
    double width = double.infinity,
    double height = 52.0,
    IconData? icon,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return SizedBox(
      width: width,
      height: height,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark
              ? (isHighContrast
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface)
              : Theme.of(context).colorScheme.onSurface,
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusM),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }

  /// Text button for text-only actions
  static Widget textButton({
    required BuildContext context,
    required String label,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return TextButton(
      onPressed: isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: isDark
            ? (isHighContrast
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface)
            : Theme.of(context).colorScheme.onSurface,
      ),
      child: isLoading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.onSurface,
                ),
              ),
            )
          : Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
    );
  }

  /// Icon button for icon-only actions
  static Widget iconButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback onPressed,
    double size = 40.0,
    Color? color,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: size,
        color:
            color ??
            (isDark
                ? (isHighContrast
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.7))
                : Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.7)),
      ),
    );
  }

  // ============================
  // INPUT FIELD COMPONENTS
  // ============================

  /// Text field with consistent styling
  static Widget appTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String hintText,
    IconData? prefixIcon,
    Widget? suffixIcon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    bool enabled = true,
    bool readOnly = false,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: isDark
              ? (isHighContrast
                    ? Color(0xFF5B6472).withValues(alpha: 0.6)
                    : Color(0xFF5B6472))
              : Color(0xFF5B6472),
          fontSize: 14,
        ),
        prefixIcon: prefixIcon != null
            ? Icon(
                prefixIcon,
                color: isDark
                    ? (isHighContrast
                          ? Color(0xFF9CA3AF).withValues(alpha: 0.6)
                          : Color(0xFF9CA3AF))
                    : Color(0xFF5B6472),
                size: 20,
              )
            : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: isDark
            ? (isHighContrast ? Color(0xFF111827) : Color(0xFF182029))
            : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(
            color: isDark
                ? (isHighContrast
                      ? Color(0xFF2D3643).withValues(alpha: 0.3)
                      : Color(0xFF2D3643))
                : Color(0xFFD3D9E1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: TextStyle(
        color: isDark
            ? (isHighContrast
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface)
            : Theme.of(context).colorScheme.onSurface,
      ),
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      enabled: enabled,
      readOnly: readOnly,
    );
  }

  /// Dropdown field with consistent styling
  static Widget appDropdown<T>({
    required BuildContext context,
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return DropdownButtonFormField<T>(
      initialValue: value,
      hint: Text(
        hint,
        style: TextStyle(
          color: isDark
              ? (isHighContrast
                    ? Color(0xFF5B6472).withValues(alpha: 0.6)
                    : Color(0xFF5B6472))
              : Color(0xFF5B6472),
          fontSize: 14,
        ),
      ),
      dropdownColor: isDark
          ? (isHighContrast ? Color(0xFF111827) : Color(0xFF182029))
          : Colors.white,
      style: TextStyle(
        color: isDark
            ? (isHighContrast
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface)
            : Theme.of(context).colorScheme.onSurface,
        fontSize: 14,
      ),
      menuMaxHeight: 300,
      decoration: InputDecoration(
        filled: true,
        fillColor: isDark
            ? (isHighContrast ? Color(0xFF111827) : Color(0xFF182029))
            : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(
            color: isDark
                ? (isHighContrast
                      ? Color(0xFF2D3643).withValues(alpha: 0.3)
                      : Color(0xFF2D3643))
                : Color(0xFFD3D9E1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      onChanged: onChanged,
      items: items,
    );
  }

  // ============================
  // SELECTION COMPONENTS
  // ============================

  /// Checkbox with consistent styling
  static Widget appCheckbox({
    required BuildContext context,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? label,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: value,
                onChanged: (bool? newValue) {
                  if (newValue != null) {
                    onChanged(newValue);
                  }
                },
                activeColor: Theme.of(context).colorScheme.primary,
                checkColor: isDark
                    ? (isHighContrast ? Colors.white : Colors.white)
                    : Colors.white,
              ),
              const SizedBox(width: spacingXS),
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  label,
                  style: TextStyle(
                    color: isDark
                        ? (isHighContrast
                              ? Colors.white.withValues(alpha: 0.8)
                              : Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.8))
                        : Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          Checkbox(
            value: value,
            onChanged: (bool? newValue) {
              if (newValue != null) {
                onChanged(newValue);
              }
            },
            activeColor: Theme.of(context).colorScheme.primary,
            checkColor: isDark
                ? (isHighContrast ? Colors.white : Colors.white)
                : Colors.white,
          ),
        ],
      ],
    );
  }

  // ============================
  // FEEDBACK COMPONENTS
  // ============================

  /// Loading indicator with consistent styling
  static Widget appLoadingIndicator({
    double size = 24.0,
    double strokeWidth = 2.0,
    Color? color,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(color ?? Colors.grey),
      ),
    );
  }

  /// Error message display
  static Widget appErrorMessage({
    required BuildContext context,
    required String message,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return Container(
      padding: EdgeInsets.all(spacingM),
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast ? Color(0xFF1A1A1A) : Color(0xFF182029))
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(radiusM),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.1)
                    : Color(0xFF2D3643))
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isDark
              ? (isHighContrast
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface)
              : Colors.red,
          fontSize: 14,
        ),
      ),
    );
  }

  /// Success message display
  static Widget appSuccessMessage({
    required BuildContext context,
    required String message,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return Container(
      padding: EdgeInsets.all(spacingM),
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast ? Color(0xFF1A1A1A) : Color(0xFF182029))
            : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(radiusM),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Colors.white.withValues(alpha: 0.1)
                    : Color(0xFF2D3643))
              : Colors.green.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isDark
              ? (isHighContrast
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface)
              : Colors.green,
          fontSize: 14,
        ),
      ),
    );
  }

  // ============================
  // AUTH COMPONENTS
  // ============================

  /// Header for authentication screens
  static Widget authHeader({
    required BuildContext context,
    required String title,
    required String subtitle,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: titleXXXL(context)),
        const SizedBox(height: spacingXS),
        Text(
          subtitle,
          style: TextStyle(
            color: isDark
                ? (isHighContrast
                      ? Color(0xFF9CA3AF).withValues(alpha: 0.8)
                      : Color(0xFF5B6472))
                : Color(0xFF5B6472),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  /// Card panel for authentication forms
  static Widget authCard({
    required BuildContext context,
    required Widget child,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast = Provider.of<ThemeController>(
      context,
      listen: false,
    ).isHighContrast;

    return Container(
      padding: EdgeInsets.all(spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? (isHighContrast ? Color(0xFF111827) : Color(0xFF182029))
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radiusL),
        border: Border.all(
          color: isDark
              ? (isHighContrast
                    ? Color(0xFF2D3643).withValues(alpha: 0.2)
                    : Color(0xFF2D3643))
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: child,
    );
  }

  // ============================
  // ENHANCED STAT COMPONENTS
  // ============================

  /// Enhanced stat card with icon, label, value, and optional description
  static Widget enhancedStatCard({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    String? description,
    double? iconSize,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? getSemanticColor(
                context,
                SemanticColor.background,
              ).withValues(alpha: 0.8)
            : getSemanticColor(context, SemanticColor.surface),
        borderRadius: BorderRadius.circular(radiusL),
        border: Border.all(
          color: isDark
              ? getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ).withValues(alpha: 0.2)
              : getSemanticColor(
                  context,
                  SemanticColor.onSurfaceVariant,
                ).withValues(alpha: 0.1),
        ),
      ),
      padding: EdgeInsets.all(spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + Label (accessibility)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(spacingXS),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.all(Radius.circular(radiusM)),
                ),
                child: Icon(icon, size: iconSize ?? 20, color: color),
              ),
              const SizedBox(width: spacingS),
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  label,
                  style: labelLarge(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? getSemanticColor(
                            context,
                            SemanticColor.onSurface,
                          ).withValues(alpha: 0.8)
                        : getSemanticColor(
                            context,
                            SemanticColor.onSurface,
                          ).withValues(alpha: 0.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: spacingXS),
          Text(
            value,
            style: titleLarge(context).copyWith(
              fontWeight: FontWeight.bold,
              color: isDark
                  ? getSemanticColor(context, SemanticColor.onSurface)
                  : getSemanticColor(context, SemanticColor.onSurface),
            ),
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: spacingXS),
            Text(
              description,
              style: caption(context).copyWith(
                color: isDark
                    ? getSemanticColor(
                        context,
                        SemanticColor.onSurfaceVariant,
                      ).withValues(alpha: 0.6)
                    : getSemanticColor(
                        context,
                        SemanticColor.onSurfaceVariant,
                      ).withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================
  // SKELETON LOADER COMPONENTS (Task 3)
  // ============================

  static Widget skeletonBox({
    required BuildContext context,
    double? width,
    double? height,
    BorderRadius? borderRadius,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color baseColor = isDark
        ? const Color(0xFF2D3039).withValues(alpha: 0.6)
        : const Color(0xFFE2E8F0).withValues(alpha: 0.8);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: borderRadius ?? BorderRadius.circular(radiusM),
      ),
    );
  }

  static Widget skeletonCard({
    required BuildContext context,
    double height = 140.0,
  }) {
    return dashboardCard(
      context: context,
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                skeletonBox(context: context, width: 36, height: 36, borderRadius: BorderRadius.circular(radiusM)),
                const SizedBox(width: spacingS),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      skeletonBox(context: context, width: 120, height: 14),
                      const SizedBox(height: spacingXS),
                      skeletonBox(context: context, width: 80, height: 10),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            skeletonBox(context: context, width: double.infinity, height: 24),
            const SizedBox(height: spacingS),
            skeletonBox(context: context, width: 160, height: 12),
          ],
        ),
      ),
    );
  }

  static Widget skeletonMetricCard({
    required BuildContext context,
  }) {
    return skeletonCard(context: context, height: 100.0);
  }

  static Widget skeletonTable({
    required BuildContext context,
    int rows = 5,
    int columns = 4,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return dashboardCard(
      context: context,
      child: Column(
        children: [
          Row(
            children: List.generate(
              columns,
              (index) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: spacingS, vertical: spacingXS),
                  child: skeletonBox(context: context, height: 16),
                ),
              ),
            ),
          ),
          const SizedBox(height: spacingM),
          Divider(color: isDark ? const Color(0xFF2D3643) : const Color(0xFFD3D9E1)),
          const SizedBox(height: spacingS),
          ...List.generate(
            rows,
            (rowIndex) => Padding(
              padding: const EdgeInsets.symmetric(vertical: spacingS),
              child: Row(
                children: List.generate(
                  columns,
                  (colIndex) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: spacingS),
                      child: skeletonBox(
                        context: context,
                        height: 14,
                        width: colIndex == 0 ? double.infinity : 60.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget skeletonList({
    required BuildContext context,
    int itemCount = 3,
    double itemHeight = 60.0,
  }) {
    return Column(
      children: List.generate(
        itemCount,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: spacingS),
          child: dashboardCard(
            context: context,
            padding: spacingM,
            child: Row(
              children: [
                skeletonBox(context: context, width: 40, height: 40, borderRadius: BorderRadius.circular(radiusM)),
                const SizedBox(width: spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      skeletonBox(context: context, width: 140, height: 14),
                      const SizedBox(height: spacingXS),
                      skeletonBox(context: context, width: 90, height: 10),
                    ],
                  ),
                ),
                skeletonBox(context: context, width: 60, height: 24, borderRadius: BorderRadius.circular(radiusS)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget skeletonChart({
    required BuildContext context,
    double height = 220.0,
  }) {
    return dashboardCard(
      context: context,
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                skeletonBox(context: context, width: 150, height: 16),
                skeletonBox(context: context, width: 80, height: 24, borderRadius: BorderRadius.circular(radiusS)),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(
                7,
                (index) => skeletonBox(
                  context: context,
                  width: 24,
                  height: (index % 2 == 0) ? height * 0.6 : height * 0.8,
                  borderRadius: BorderRadius.circular(radiusXS),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
