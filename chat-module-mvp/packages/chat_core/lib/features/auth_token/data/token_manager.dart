import 'dart:convert';
import 'package:http/http.dart' as http;

import '../domain/auth_token_repository.dart';
import '../domain/chat_access_token.dart';
import '../domain/chat_auth_token_provider.dart';

/// Cache ACS token trong memory, tự gọi lại BE khi [ChatAccessToken.needsRefresh].
/// Không dùng storage bền (SharedPreferences...) — token sống ngắn, không
/// cần cache qua session, đúng nguyên tắc "Startup: không block UI chờ
/// token, cache token theo expiresOn" ở mục 6 kế hoạch gốc.
class TokenManager implements AuthTokenRepository {
  TokenManager({
    required this.backendBaseUrl,
    required this.appTokenProvider,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String backendBaseUrl;
  final ChatAuthTokenProvider appTokenProvider;
  final http.Client _http;

  ChatAccessToken? _cached;
  Future<ChatAccessToken>? _inFlight;

  /// Tránh gọi trùng nhiều request refresh cùng lúc nếu nhiều nơi trong
  /// app đồng thời cần token (vd nhiều thread mở song song).
  @override
  Future<ChatAccessToken> getAccessToken() {
    final cached = _cached;
    if (cached != null && !cached.needsRefresh) {
      return Future.value(cached);
    }
    return _inFlight ??= _refresh().whenComplete(() => _inFlight = null);
  }

  Future<ChatAccessToken> _refresh() async {
    final appToken = await appTokenProvider.getAppToken();
    final response = await _http.post(
      Uri.parse('$backendBaseUrl/auth/communication-token'),
      headers: {
        'Authorization': 'Bearer $appToken',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw ChatAccessTokenException(
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final token = ChatAccessToken.fromJson(json['data'] as Map<String, dynamic>);
    _cached = token;
    return token;
  }

  void dispose() => _http.close();
}

class ChatAccessTokenException implements Exception {
  ChatAccessTokenException({required this.statusCode, required this.body});
  final int statusCode;
  final String body;

  @override
  String toString() => 'ChatAccessTokenException($statusCode): $body';
}
