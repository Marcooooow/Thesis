import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'routes/auth_gate.dart';
import 'core/theme/theme_controller.dart';
import 'features/dashboard/providers/break_coach_state.dart';
import 'features/dashboard/providers/profile_provider.dart';
import 'providers/work_session_provider.dart';
import 'providers/shift_timer_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/team_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/presence_provider.dart';
import 'features/messaging/providers/messaging_provider.dart';
import 'features/attendance/providers/attendance_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    const IntelliBreakApp(),
  );
}

class IntelliBreakApp extends StatelessWidget {
  const IntelliBreakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Core providers - always needed
        ChangeNotifierProvider(create: (_) => ThemeController()),

        // Dashboard providers - needed for authenticated screens
        ChangeNotifierProvider(create: (_) => BreakCoachState()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => ShiftTimerProvider()),

        // Session/work providers - initialized after auth in AuthGate
        ChangeNotifierProvider(create: (_) => WorkSessionProvider()),
        ChangeNotifierProvider(create: (_) => PresenceProvider()),

        // Other providers
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => TeamProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => MessagingProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themeController, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'IntelliBreak',
            theme: themeController.getThemeData(context),
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}