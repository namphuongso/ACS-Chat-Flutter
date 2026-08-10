/// Map theo error code registry api-docs mục 11.2. MVP chỉ xử lý các mã
/// liên quan trực tiếp đến luồng direct chat — không xử lý hết 20 mã
/// (nhóm group/roles/file chưa có ở MVP, theo đúng roadmap "rải đều,
/// không dồn cuối").
class ChatApiException implements Exception {
  ChatApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

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
