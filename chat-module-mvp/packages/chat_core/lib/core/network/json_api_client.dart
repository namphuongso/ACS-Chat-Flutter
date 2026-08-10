import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../error/chat_api_exception.dart';

/// Client http dùng chung cho các remote datasource (BE nội bộ):
/// tự gắn Bearer token, decode envelope `{ data }`, map lỗi HTTP sang
/// [ChatApiException]. Giúp datasource không lặp lại logic header/error/parse.
///
/// Chỉ dùng cho các endpoint BE trả envelope chuẩn — endpoint ACS trực tiếp
/// (list message, realtime) có envelope khác (`value`/`nextLink`) nên tự xử lý.
class JsonApiClient {
  JsonApiClient({required String backendBaseUrl, http.Client? httpClient})
      : _base = backendBaseUrl,
        _http = httpClient ?? http.Client();

  final String _base;
  final http.Client _http;

  Future<dynamic> get(
    String path, {
    required String appToken,
    Map<String, String>? query,
    bool allowEmptyBody = false,
  }) async {
    final uri = query == null
        ? Uri.parse('$_base$path')
        : Uri.parse('$_base$path').replace(queryParameters: query);
    developer.log('GET Request: $uri', name: 'ChatModule');
    final response = await _http
        .get(uri, headers: _jsonHeaders(appToken))
        .timeout(const Duration(seconds: 15));
    developer.log('GET Response [${response.statusCode}]: ${response.body}',
        name: 'ChatModule');
    return _decodeOrThrow(response, allowEmptyBody: allowEmptyBody);
  }

  Future<dynamic> post(
    String path, {
    required String appToken,
    Object? body,
    Map<String, String>? query,
    bool allowEmptyBody = false,
  }) async {
    final uri = query == null
        ? Uri.parse('$_base$path')
        : Uri.parse('$_base$path').replace(queryParameters: query);
    final jsonBody = body == null ? null : jsonEncode(body);
    developer.log('POST Request: $uri\nBody: $jsonBody', name: 'ChatModule');

    final response = await _http
        .post(
          uri,
          headers: _jsonHeaders(appToken),
          body: jsonBody,
        )
        .timeout(const Duration(seconds: 15));
    developer.log('POST Response [${response.statusCode}]: ${response.body}',
        name: 'ChatModule');
    return _decodeOrThrow(response, allowEmptyBody: allowEmptyBody);
  }

  Map<String, String> _jsonHeaders(String appToken) => {
        'Authorization': 'Bearer $appToken',
        'Content-Type': 'application/json',
      };

  dynamic _decodeOrThrow(http.Response response,
      {bool allowEmptyBody = false}) {
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

  void dispose() => _http.close();
}
