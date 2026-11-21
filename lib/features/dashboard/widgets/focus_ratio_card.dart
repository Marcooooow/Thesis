import 'package:flutter/material.dart';

class FocusRatioCard extends StatelessWidget {
  const FocusRatioCard({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222532) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF303442) : const Color(0xFFD3D9E1),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today\'s Focus Ratio',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 24),
          _buildFocusBars(isDark),
        ],
      ),
    );
  }

  Widget _buildFocusBars(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Active Focus bar
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                'Active Focus:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
              ),
            ),
            Expanded(
              flex: 7,
              child: Container(
                height: 24,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF111827)
                      : const Color(0xFFECEFF3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF303442)
                        : const Color(0xFFD3D9E1),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        // Background (non-active)
                        Container(
                          width: constraints.maxWidth,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF111827)
                                : const Color(0xFFECEFF3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        // Active portion
                        Container(
                          width: constraints.maxWidth * 0.8, // 80% active
                          height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Non-Active bar
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                'Non-Active:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
              ),
            ),
            Expanded(
              flex: 7,
              child: Container(
                height: 24,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF111827)
                      : const Color(0xFFECEFF3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF303442)
                        : const Color(0xFFD3D9E1),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        // Background (non-active)
                        Container(
                          width: constraints.maxWidth,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF111827)
                                : const Color(0xFFECEFF3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        // Non-active portion
                        Container(
                          width: constraints.maxWidth * 0.2, // 20% non-active
                          height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFF9CA3AF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
