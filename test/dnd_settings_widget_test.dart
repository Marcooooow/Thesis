import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/providers/settings_provider.dart';
import 'package:intellibreak/providers/work_session_provider.dart';
import 'package:intellibreak/providers/work_session_models.dart';
import 'package:intellibreak/features/dashboard/widgets/greeting_section.dart';

class MockSettingsProvider extends SettingsProvider {
  Map<String, dynamic> mockSettings = {'manual_dnd_override': null};
  bool updateCalled = false;
  Map<String, dynamic>? lastUpdate;

  @override
  Map<String, dynamic> get settings => mockSettings;

  @override
  bool? get manualDndOverride => mockSettings['manual_dnd_override'];

  @override
  Future<void> updateSettings(Map<String, dynamic> updateData) async {
    updateCalled = true;
    lastUpdate = updateData;
    mockSettings.addAll(updateData);
    notifyListeners();
  }
}

class MockWorkSessionProvider extends ChangeNotifier implements WorkSessionProvider {
  final bool _active;
  MockWorkSessionProvider({bool active = false}) : _active = active;

  @override
  bool get isActive => _active;

  @override
  bool get isOnBreak => false;

  @override
  BreakType? get breakType => null;

  @override
  DateTime? get startTime => null;

  @override
  int? get elapsedTimeInSeconds => null;

  @override
  Set<BreakType> get breaksTaken => {};

  @override
  WorkTask? get currentTask => null;

  @override
  WorkTask? get unfinishedTask => null;

  @override
  DateTime? get meetingStartedAt => null;

  @override
  DateTime? get meetingEndedAt => null;

  @override
  bool get isLoading => false;

  @override
  String? get lastError => null;

  @override
  bool get isOnline => true;

  @override
  WorkSessionState get state => WorkSessionState.empty;

  @override
  Future<void> endShift() async {}

  @override
  Future<void> startShift() async {}

  @override
  Future<void> refresh({String? token}) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> startBreak(BreakType type, {String? recommendationId}) async {}

  @override
  Future<void> endBreak() async {}

  @override
  Future<void> extendBreak({int extensionMinutes = 15, String? reason}) async {}

  @override
  void setCurrentTask(WorkTask? task) {}

  @override
  void clear() {}

  @override
  BreakAvailability availabilityFor(BreakType type) => BreakAvailability.available();
}

void main() {
  testWidgets('GreetingSection displays DND ON / OFF correctly based on shift and settings', (WidgetTester tester) async {
    final settingsProvider = MockSettingsProvider();
    final workSessionProvider = MockWorkSessionProvider(active: false); // off-shift -> auto DND ON

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
            ChangeNotifierProvider<WorkSessionProvider>.value(value: workSessionProvider),
          ],
          child: const Scaffold(
            body: GreetingSection(isGuest: true),
          ),
        ),
      ),
    );

    expect(find.textContaining('DND: ON'), findsOneWidget);
    expect(find.textContaining('(Automatic)'), findsOneWidget);

    // Change to Force OFF
    settingsProvider.mockSettings['manual_dnd_override'] = false;
    settingsProvider.notifyListeners();
    await tester.pump();

    expect(find.textContaining('DND: OFF'), findsOneWidget);
    expect(find.textContaining('(Forced OFF)'), findsOneWidget);

    // Change to Force ON
    settingsProvider.mockSettings['manual_dnd_override'] = true;
    settingsProvider.notifyListeners();
    await tester.pump();

    expect(find.textContaining('DND: ON'), findsOneWidget);
    expect(find.textContaining('(Forced ON)'), findsOneWidget);
  });
}
