import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intellibreak/features/admin/screens/ml_explainability_dashboard_screen.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/core/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MalformedHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.path;
    Map<String, dynamic> responseBody = {};
    if (url.contains('scoring-engine')) {
      responseBody = {
        'weights': "malformed_string_instead_of_map",
        'candidate_adjustments': ["malformed_list_instead_of_map"],
      };
    } else if (url.contains('prediction-inspector')) {
      responseBody = {
        'context_features': "malformed_features_string",
      };
    } else if (url.contains('feature-importance')) {
      responseBody = {
        'feature_importance': 12345,
      };
    } else {
      responseBody = {'status': 'ok'};
    }
    return http.StreamedResponse(
      Stream.fromIterable([utf8.encode(jsonEncode(responseBody))]),
      200,
    );
  }
}

void main() {
  testWidgets('MLExplainabilityDashboardScreen handles malformed API map data safely without throwing TypeError', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'test-token'});
    final apiService = ApiService(client: _MalformedHttpClient());

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

    await tester.pumpAndSettle();

    // Verify app rendered without crashing with TypeError on .entries
    expect(find.byType(MLExplainabilityDashboardScreen), findsOneWidget);
  });
}
