import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/features/auth/services/auth_service.dart';
import 'package:intellibreak/providers/settings_provider.dart';
import 'package:intellibreak/providers/work_session_provider.dart';

class GreetingSection extends StatefulWidget {
  final bool isGuest;
  final String? userName;

  const GreetingSection({super.key, this.isGuest = false, this.userName});

  @override
  State<GreetingSection> createState() => _GreetingSectionState();
}

class _GreetingSectionState extends State<GreetingSection> {
  late DateTime _currentTime;
  Timer? _timer;

  final List<String> _quotes = const [
    "Small progress each day adds up to meaningful results.",
    "Stay focused, work steadily, and remember to take meaningful breaks.",
    "Progress comes from consistent effort, not constant effort.",
    "Focus on what matters most today.",
    "Work with intention and give yourself time to recover.",
    "A balanced workday is a productive workday.",
    "Make steady progress without forgetting to recharge.",
  ];

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If returning from background / tab switch, immediately refresh to real time
    if (mounted) {
      _currentTime = DateTime.now();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isHighContrast =
        Theme.of(context).colorScheme.brightness == Brightness.dark &&
        Theme.of(context).dividerTheme.color ==
            Colors.white.withValues(alpha: 0.15) &&
        Theme.of(context).dividerTheme.thickness == 2;

    final int hour = _currentTime.hour;
    String greeting;
    if (hour >= 5 && hour < 12) {
      greeting = 'Good morning';
    } else if (hour >= 12 && hour < 17) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }

    String displayName;
    if (widget.isGuest) {
      displayName = 'Guest';
    } else if (widget.userName != null && widget.userName!.isNotEmpty) {
      displayName = widget.userName!;
    } else {
      final String? fallback = AuthService().getUserDisplayName();
      displayName = fallback ?? 'User';
    }

    final int index = (displayName.hashCode.abs() % _quotes.length + _currentTime.day % _quotes.length) % _quotes.length;
    final String quote = _quotes[index.abs() % _quotes.length];

    final String dateStr = '${_currentTime.month}/${_currentTime.day}/${_currentTime.year}';
    final String timeStr = '${_currentTime.hour}:${_currentTime.minute.toString().padLeft(2, '0')}';

    final settingsProvider = Provider.of<SettingsProvider>(context);
    final workSessionProvider = Provider.of<WorkSessionProvider>(context);
    final manualOverride = settingsProvider.manualDndOverride;
    final hasActiveSession = workSessionProvider.isActive;
    final automaticDnd = !hasActiveSession;
    final effectiveDnd = manualOverride ?? automaticDnd;
    final modeLabel = manualOverride == null ? 'Automatic' : (manualOverride ? 'Forced ON' : 'Forced OFF');

    final textColor = isDark
        ? (isHighContrast ? Colors.white : Color(0xFFE8EBEF))
        : Color(0xFF111827);
    final subColor = isDark
        ? (isHighContrast ? Colors.white70 : Color(0xFF9CA3AF))
        : Color(0xFF5B6472);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, $displayName',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                quote,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.normal,
                  color: subColor,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$dateStr  •  $timeStr',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: subColor,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: effectiveDnd ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: effectiveDnd ? Colors.red.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    effectiveDnd ? Icons.notifications_off : Icons.notifications_active,
                    size: 14,
                    color: effectiveDnd ? Colors.red : Colors.green,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'DND: ${effectiveDnd ? 'ON' : 'OFF'} ($modeLabel)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: effectiveDnd ? Colors.red.shade700 : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
