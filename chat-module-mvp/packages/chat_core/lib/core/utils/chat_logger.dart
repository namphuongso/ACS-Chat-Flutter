import 'dart:convert';
import 'dart:developer' as developer;

/// Logger tiện ích cho Chat Module: tự động format JSON đẹp (pretty print) cho các request / response HTTP.
class ChatLogger {
  static const _encoder = JsonEncoder.withIndent('  ');
  static bool enabled = const bool.fromEnvironment('CHAT_DEBUG_LOG', defaultValue: false);

  static void log(String message, {String tag = 'ChatModule'}) {
    if (!enabled) return;
    developer.log(message, name: tag);
  }

  static Map<String, String> _sanitizeHeaders(Map<String, String>? headers) {
    if (headers == null) return const {};
    final sanitized = Map<String, String>.from(headers);
    for (final key in sanitized.keys.toList()) {
      if (key.toLowerCase() == 'authorization') {
        sanitized[key] = 'Bearer ***';
      }
    }
    return sanitized;
  }

  /// In log Request HTTP dạng pretty JSON
  static void logRequest(
    String method,
    dynamic uri, {
    Map<String, String>? headers,
    Object? body,
    String tag = 'ChatModule',
  }) {
    if (!enabled) return;
    final sb = StringBuffer('$method Request: $uri');
    if (headers != null && headers.isNotEmpty) {
      sb.write('\nHeaders: ');
      sb.write(_prettyJson(_sanitizeHeaders(headers)));
    }
    if (body != null) {
      sb.write('\nBody: ');
      sb.write(_prettyJson(body));
    }
    developer.log(sb.toString(), name: tag);
  }

  /// In log Response HTTP dạng pretty JSON
  static void logResponse(
    String method,
    dynamic uri,
    int statusCode,
    String responseBody, {
    String tag = 'ChatModule',
  }) {
    if (!enabled) return;
    final sb = StringBuffer('$method Response [$statusCode]: $uri\nBody:\n');
    sb.write(_prettyJson(responseBody));
    developer.log(sb.toString(), name: tag);
  }

  static String _prettyJson(Object body) {
    try {
      if (body is String) {
        final trimmed = body.trim();
        if (trimmed.isEmpty) return '';
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          final parsed = jsonDecode(trimmed);
          return _encoder.convert(parsed);
        }
        return trimmed;
      }
      return _encoder.convert(body);
    } catch (_) {
      return body.toString();
    }
  }
}
