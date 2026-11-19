import 'package:intellibreak/features/auth/services/api_service.dart';

class MessagingService {
  static final ApiService _api = ApiService();
  static const String _prefix = '/messages';

  static Future<Map<String, dynamic>> getConversations(String token) async {
    final resp = await _api.getMapWithAuth(_prefix, token);
    return resp ?? {};
  }

  static Future<List<dynamic>> getOrganizationMembers(String token) async {
    final resp = await _api.getListWithAuth('$_prefix/members', token);
    return resp;
  }

  static Future<Map<String, dynamic>> createDirect(String token, String recipientId) async {
    final resp = await _api.postWithAuth(
      '$_prefix/conversations',
      token,
      {'recipient_user_id': recipientId},
    );
    return resp;
  }

  static Future<Map<String, dynamic>> getMessages(String token, String convoId, {int limit = 20, int offset = 0}) async {
    final resp = await _api.getMapWithAuth('$_prefix/conversations/$convoId/messages?limit=$limit&offset=$offset', token);
    return resp ?? {};
  }

  static Future<Map<String, dynamic>> sendMessage(String token, String convoId, String content) async {
    final resp = await _api.postWithAuth(
      '$_prefix/conversations/$convoId/messages',
      token,
      {'content': content},
    );
    return resp;
  }

  static Future<Map<String, dynamic>> markRead(String token, String convoId) async {
    final resp = await _api.postWithAuth('$_prefix/conversations/$convoId/read', token, {});
    return resp;
  }
}
