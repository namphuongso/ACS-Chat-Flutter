import '../../../../core/domain/entities/chat_user.dart';

/// Kết quả từ `POST /api/auth/communication-token`.
class ChatAccessToken {
  const ChatAccessToken({
    required this.token,
    required this.expiresOn,
    required this.acsUserId,
    this.participants = const [],
  });

  final String token;
  final DateTime expiresOn;
  final String acsUserId;
  final List<ChatUser> participants;

  bool get isExpired => DateTime.now().isAfter(expiresOn);

  /// Coi là "sắp hết hạn" trước 2 phút để chủ động refresh, tránh
  /// race-condition ngay lúc gọi API mà token vừa hết hạn.
  bool get needsRefresh =>
      DateTime.now().isAfter(expiresOn.subtract(const Duration(minutes: 2)));
}
