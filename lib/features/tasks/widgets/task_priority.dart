import 'package:flutter/material.dart';

/// Colour language for task priority, used on task cards and borders.
///
/// Colours are paired with a text label everywhere they appear, so priority is
/// never conveyed by colour alone.
class TaskPriorityStyle {
  static const Color low = Color(0xFF2F8F6B);
  static const Color medium = Color(0xFFB7871F);
  static const Color high = Color(0xFFD9722E);
  static const Color urgent = Color(0xFFC2433D);

  static Color color(String? priority) {
    switch ((priority ?? 'MEDIUM').toUpperCase()) {
      case 'LOW':
        return low;
      case 'HIGH':
        return high;
      case 'URGENT':
      case 'CRITICAL':
        return urgent;
      default:
        return medium;
    }
  }

  static String label(String? priority) {
    final p = (priority ?? 'MEDIUM').toUpperCase();
    return p[0] + p.substring(1).toLowerCase();
  }

  /// Border for a task card, tinted by priority.
  static BorderSide border(String? priority) =>
      BorderSide(color: color(priority).withValues(alpha: 0.75), width: 1.5);

  /// Small pill: dot + label.
  static Widget badge(String? priority, {double fontSize = 12}) {
    final c = color(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            '${label(priority)} priority',
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: c),
          ),
        ],
      ),
    );
  }
}
