import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/admin/screens/ml_explainability_dashboard_screen.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mock HTTP client that always returns 404, triggering the default fallback path.
class _FailingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.fromIterable([utf8.encode('{}')]),
      404,
    );
  }
}

void main() {
  testWidgets(
      'ML explainability dashboard default fallback uses backend threshold (20)',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'test-token'});

    final apiService = ApiService(client: _FailingHttpClient());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MLExplainabilityDashboardScreen(apiService: apiService),
          ),
        ),
      ),
    );

    // Let _initData() + all six loaders complete (they all fail and fall back).
    await tester.pumpAndSettle();

    // The default fallback now uses min_required: 20 (from backend constant),
    // not a hardcoded 200.
    expect(find.textContaining(' / 20'), findsWidgets);

    // The hardcoded 200 must never appear.
    expect(find.textContaining(' / 200'), findsNothing);
  });
}