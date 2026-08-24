/// Lớp cơ sở cho toàn bộ ngoại lệ trong Chat Module.
abstract class ChatException implements Exception {
  String get code;
  String get message;
  bool get isHttpError;
}

/// Ngoại lệ ném ra khi giao tiếp REST HTTP thất bại với HTTP status code (4xx, 5xx).
class ChatApiException extends ChatException {
  ChatApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  @override
  final String code;
  @override
  final String message;

  @override
  bool get isHttpError => true;

  bool get isUnauthorized => statusCode == 401;
  bool get isRateLimited => statusCode == 429;
  bool get isNotFound => statusCode == 404;

  factory ChatApiException.fromResponseBody(
    int statusCode,
    Map<String, dynamic> json,
  ) {
    return ChatApiException(
      statusCode: statusCode,
      code: (json['code'] as String?) ?? 'UNKNOWN',
      message: (json['message'] as String?) ?? 'Unknown error',
    );
  }

  @override
  String toString() => 'ChatApiException($statusCode $code): $message';
}

/// Ngoại lệ dành cho trường hợp phản hồi API trả về dữ liệu rỗng, sai định dạng
/// hoặc thiếu thông tin xử lý (không phải do lỗi kết nối HTTP status code 4xx/5xx).
class ChatDataException extends ChatException {
  ChatDataException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  @override
  final String code;
  @override
  final String message;
  final int? statusCode;

  @override
  bool get isHttpError => false;

  @override
  String toString() => 'ChatDataException($code): $message';
}
