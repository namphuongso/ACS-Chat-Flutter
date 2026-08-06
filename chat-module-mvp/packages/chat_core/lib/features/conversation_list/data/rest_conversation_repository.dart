import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../auth_token/domain/chat_auth_token_provider.dart';
import '../../shared/chat_api_exception.dart';
import '../../shared/chat_module_config.dart';
import '../domain/conversation.dart';
import '../domain/conversation_repository.dart';

class RestConversationRepository implements ConversationRepository {
  RestConversationRepository({
    required ChatModuleConfig config,
    required ChatAuthTokenProvider appTokenProvider,
    http.Client? httpClient,
  })  : _config = config,
        _appTokenProvider = appTokenProvider,
        _http = httpClient ?? http.Client();

  final ChatModuleConfig _config;
  final ChatAuthTokenProvider _appTokenProvider;
  final http.Client _http;

  @override
  Future<Conversation> getOrCreateDirectConversation(String otherUserId) async {
    final appToken = await _appTokenProvider.getAppToken();
    final response = await _http.post(
      Uri.parse('${_config.backendBaseUrl}/conversations/direct'),
      headers: _jsonHeaders(appToken),
      body: jsonEncode({'targetUserId': otherUserId}),
    );
    final data = _decodeOrThrow(response);
    return Conversation.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<PaginatedResult<Conversation>> listConversations({
    String? cursor,
    int limit = 20,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final query = {
      'limit': '$limit',
      'type': 'direct',
      if (cursor != null) 'cursor': cursor,
    };
    final uri = Uri.parse('${_config.backendBaseUrl}/conversations')
        .replace(queryParameters: query);
    final response = await _http.get(uri, headers: _jsonHeaders(appToken));
    final data = _decodeOrThrow(response) as Map<String, dynamic>;

    final items = (data['items'] as List)
        .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
        .toList();
    final pagination = data['pagination'] as Map<String, dynamic>;
    return PaginatedResult(
      items: items,
      hasMore: pagination['hasMore'] as bool? ?? false,
      cursor: pagination['cursor'] as String?,
    );
  }

  @override
  Future<Conversation> getConversation(String conversationId) async {
    final appToken = await _appTokenProvider.getAppToken();
    final response = await _http.get(
      Uri.parse('${_config.backendBaseUrl}/conversations/$conversationId'),
      headers: _jsonHeaders(appToken),
    );
    final data = _decodeOrThrow(response);
    return Conversation.fromJson(data as Map<String, dynamic>);
  }

  Map<String, String> _jsonHeaders(String appToken) => {
        'Authorization': 'Bearer $appToken',
        'Content-Type': 'application/json',
      };

  dynamic _decodeOrThrow(http.Response response, {bool allowEmptyBody = false}) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final json = _tryDecode(response.body);
      if (json != null) {
        throw ChatApiException.fromResponseBody(response.statusCode, json);
      }
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'UNKNOWN',
        message: response.body,
      );
    }
    if (allowEmptyBody && response.body.isEmpty) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['data'];
  }

  Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
