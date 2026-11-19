import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecommendationService {
  final ApiService _apiService = ApiService();

  Future<Map<String, dynamic>> generateRecommendation() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token')?.trim();
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated');
    }
    try {
      return await _apiService.postWithAuth('/recommend/generate', token, {});
    } catch (e, st) {
      print('[RECOMMEND SERVICE] EXACT EXCEPTION TYPE: ${e.runtimeType}');
      print('[RECOMMEND SERVICE] EXACT MESSAGE: $e');
      print('[RECOMMEND SERVICE] STACK TRACE FIRST 8 LINES:');
      for (final line in st.toString().split('\n').take(8)) {
        print('  $line');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> submitFeedback(
    String recommendationId,
    String userAction,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token')?.trim();
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated');
    }
    // Only send user_action and recommendation_id; no fabricated outcome fields
    final body = <String, dynamic>{
      'recommendation_id': recommendationId,
      'user_action': userAction,
    };
    final response = await _apiService.postWithAuth(
      '/recommend/feedback',
      token,
      body,
    );
    return response;
  }
}