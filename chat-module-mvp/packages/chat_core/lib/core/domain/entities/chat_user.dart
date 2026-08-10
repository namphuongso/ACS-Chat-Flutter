/// Thông tin user ứng dụng (không phải ACS identity thô).
///
/// [acsUserId] chỉ có khi lấy từ `/api/auth/communication-token` hoặc
/// `ParticipantResponse` — API `/api/users/search` KHÔNG trả acsUserId
/// (theo ghi chú bảo mật trong api-docs mục 9.1), nên field này nullable.
class ChatUser {
  const ChatUser({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.acsUserId,
    this.email,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? acsUserId;
  final String? email;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ChatUser && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
