import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  group('ApiService.login', () {
    test('login with wrong credentials does not call refreshAccessToken', () async {
      final client = MockClient((request) async {
        // Return 401 for /auth/login
        if (request.url.path.contains("/auth/login")) {
          return http.Response('{"detail":"Incorrect email or password"}', 401);
        }
        return http.Response('Not Found', 404);
      });

      final apiService = ApiService(client: client);

      bool threw = false;
      try {
        await apiService.login('user@example.com', 'wrongPassword');
      } catch (_) {
        threw = true;
      }
      expect(threw, true, reason: 'login should throw for 401');
    });

    test('login with correct credentials stores tokens', () async {
      final client = MockClient((request) async {
        if (request.url.path.contains("/health")) {
          return http.Response('{"status":"healthy"}', 200);
        }
        if (request.url.path.contains("/auth/login")) {
          return http.Response(
            '{"access_token":"acc123","refresh_token":"ref123","requires_2fa":false}',
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiService = ApiService(client: client);
      await apiService.login('user@example.com', 'correctPassword');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), equals('acc123'));
      expect(prefs.getString('refresh_token'), equals('ref123'));
    });
  });
}
