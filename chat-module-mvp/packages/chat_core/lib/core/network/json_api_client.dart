import 'dart:convert';
import 'package:http/http.dart' as http;

import '../error/chat_api_exception.dart';
import '../utils/chat_logger.dart';

/// Client http dùng chung cho các remote datasource (BE nội bộ):
/// tự gắn Bearer token, decode envelope `{ data }`, map lỗi HTTP sang
/// [ChatApiException]. Giúp datasource không lặp lại logic header/error/parse.
///
/// Chỉ dùng cho các endpoint BE trả envelope chuẩn — endpoint ACS trực tiếp
/// (list message, realtime) có envelope khác (`value`/`nextLink`) nên tự xử lý.
class JsonApiClient {
  JsonApiClient({
    required String backendBaseUrl,
    this.apiKey,
    http.Client? httpClient,
  })  : _base = backendBaseUrl,
        _http = httpClient ?? http.Client();

  final String _base;
  final String? apiKey;
  final http.Client _http;

  String get backendBaseUrl => _base;

  Future<dynamic> get(
    String path, {
    required String appToken,
    Map<String, String>? query,
    bool allowEmptyBody = false,
  }) async {
    final uri = query == null
        ? Uri.parse('$_base$path')
        : Uri.parse('$_base$path').replace(queryParameters: query);
    ChatLogger.logRequest('GET', uri);
    final response = await _http
        .get(uri, headers: _jsonHeaders(appToken))
        .timeout(const Duration(seconds: 15));
    ChatLogger.logResponse('GET', uri, response.statusCode, response.body);
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
    ChatLogger.logRequest('POST', uri, body: body);

    final response = await _http
        .post(
          uri,
          headers: _jsonHeaders(appToken),
          body: jsonBody,
        )
        .timeout(const Duration(seconds: 15));
    ChatLogger.logResponse('POST', uri, response.statusCode, response.body);
    return _decodeOrThrow(response, allowEmptyBody: allowEmptyBody);
  }

  Future<dynamic> put(
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
    ChatLogger.logRequest('PUT', uri, body: body);

    final response = await _http
        .put(
          uri,
          headers: _jsonHeaders(appToken),
          body: jsonBody,
        )
        .timeout(const Duration(seconds: 15));
    ChatLogger.logResponse('PUT', uri, response.statusCode, response.body);
    return _decodeOrThrow(response, allowEmptyBody: allowEmptyBody);
  }

  Future<dynamic> uploadFiles(
    String path, {
    required String appToken,
    required List<({String path, String filename})> files,
    String fieldName = 'file',
  }) async {
    final uri = Uri.parse('$_base$path');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $appToken';
    if (apiKey != null && apiKey!.isNotEmpty) {
      request.headers['X-API-KEY'] = apiKey!;
    }
    for (final file in files) {
      request.files.add(await http.MultipartFile.fromPath(
        fieldName,
        file.path,
        filename: file.filename,
      ));
    }
    ChatLogger.logRequest('POST Multipart', uri, body: {'files': files.length});
    final streamed =
        await _http.send(request).timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    ChatLogger.logResponse('POST Multipart', uri, response.statusCode, response.body);
    return _decodeOrThrow(response);
  }

  Map<String, String> _jsonHeaders(String appToken) => {
        'Authorization': 'Bearer $appToken',
        'Content-Type': 'application/json',
        if (apiKey != null && apiKey!.isNotEmpty) 'X-API-KEY': apiKey!,
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
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded.containsKey('data') ? decoded['data'] : decoded;
      }
      return decoded;
    } catch (e) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'INVALID_RESPONSE',
        message: 'Không thể giải mã dữ liệu phản hồi từ server: $e',
      );
    }
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
