import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../auth_token/domain/chat_auth_token_provider.dart';
import '../../shared/chat_api_exception.dart';
import '../../shared/chat_module_config.dart';
import '../domain/read_status_repository.dart';

class RestReadStatusRepository implements ReadStatusRepository {
  RestReadStatusRepository({
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
  Future<void> markAsRead(String conversationId) async {
    final appToken = await _appTokenProvider.getAppToken();
    final response = await _http.post(
      Uri.parse('${_config.backendBaseUrl}/conversations/$conversationId/read'),
      headers: _jsonHeaders(appToken),
    );
    _decodeOrThrow(response, allowEmptyBody: true);
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
