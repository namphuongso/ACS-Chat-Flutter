import '../../shared/chat_user.dart';

/// Kết quả từ `POST /api/auth/communication-token`.
class ChatAccessToken {
  const ChatAccessToken({
    required this.token,
    required this.expiresOn,
    required this.user,
    required this.endpoint,
  });

  final String token;
  final DateTime expiresOn;
  final ChatUser user;

  /// ACS resource endpoint, dùng để build URL gọi ACS REST trực tiếp
  /// (send/list message, typing, read receipt).
  final String endpoint;

  bool get isExpired => DateTime.now().isAfter(expiresOn);

  /// Coi là "sắp hết hạn" trước 2 phút để chủ động refresh, tránh
  /// race-condition ngay lúc gọi API mà token vừa hết hạn.
  bool get needsRefresh =>
      DateTime.now().isAfter(expiresOn.subtract(const Duration(minutes: 2)));

  factory ChatAccessToken.fromJson(Map<String, dynamic> json) {
    return ChatAccessToken(
      token: json['token'] as String,
      expiresOn: DateTime.parse(json['expiresOn'] as String),
      user: ChatUser.fromJson(json['user'] as Map<String, dynamic>),
      endpoint: json['endpoint'] as String,
    );
  }
}
