import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';

class PasswordStrengthIndicator extends StatelessWidget {
  final String password;
  final String confirmPassword;

  const PasswordStrengthIndicator({
    super.key,
    required this.password,
    required this.confirmPassword,
  });

  PasswordStrength _calculateStrength() {
    if (password.isEmpty) {
      return PasswordStrength.empty;
    }

    // Gate: minimum 12 characters required
    if (password.length < 12) {
      return PasswordStrength.weak;
    }

    int score = 0;

    // Minimum met: 12+ chars = baseline
    score++;

    // Extra length: 20+ chars = bonus point
    if (password.length >= 20) score++;

    // Diversity markers
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[a-z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;

    const specialChars = '!@#\$%^&*()_+-=[]{};<>,.?/~`|:';
    if (password.split('').any((c) => specialChars.contains(c))) score++;

    // 12+ chars alone = Fair (score 1)
    // 12+ chars + 2+ diversity = Good (score 3+)
    // 20+ chars + 2+ diversity = Strong (score 4+)
    if (score >= 4) return PasswordStrength.strong;
    if (score >= 3) return PasswordStrength.good;
    return PasswordStrength.fair;
  }

  @override
  Widget build(BuildContext context) {
    final strength = _calculateStrength();
    final hasMatch = password == confirmPassword && password.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Password strength bar
        if (password.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: strength.value,
                  minHeight: 4,
                  backgroundColor: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant)
                      .withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(strength.color),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                strength.label,
                style: TextStyle(
                  color: strength.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        // Password match feedback
        if (confirmPassword.isNotEmpty)
          Row(
            children: [
              Icon(
                hasMatch ? Icons.check_circle : Icons.cancel,
                size: 16,
                color: hasMatch ? Colors.green : Colors.redAccent,
              ),
              const SizedBox(width: 8),
              Text(
                hasMatch ? 'Passwords match' : 'Passwords do not match',
                style: TextStyle(
                  color: hasMatch ? Colors.green : Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

enum PasswordStrength {
  empty('', 0),
  weak('Below 12 characters', 0.33),
  fair('Fair (12+ chars)', 0.66),
  good('Good', 0.8),
  strong('Strong', 1.0);

  final String label;
  final double value;

  const PasswordStrength(this.label, this.value);

  Color get color {
    switch (this) {
      case PasswordStrength.empty:
        return Colors.grey;
      case PasswordStrength.weak:
        return Colors.redAccent;
      case PasswordStrength.fair:
        return Colors.orange;
      case PasswordStrength.good:
        return Colors.amber;
      case PasswordStrength.strong:
        return Colors.green;
    }
  }
}
