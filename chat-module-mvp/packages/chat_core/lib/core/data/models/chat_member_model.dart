import '../../domain/entities/chat_member.dart';

class ChatMemberModel extends ChatMember {
  const ChatMemberModel({
    required super.id,
    required super.displayName,
    super.avatarUrl,
    super.acsUserId,
    super.email,
    super.isAdmin,
  });

  factory ChatMemberModel.fromJson(Map<String, dynamic> json) {
    return ChatMemberModel(
      id: (json['id'] as String?) ?? (json['userId'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ??
          (json['fullName'] as String?) ??
          (json['contactName'] as String?) ??
          '',
      avatarUrl: json['avatarUrl'] as String?,
      acsUserId: (json['acsUserId'] as String?) ?? (json['cui'] as String?),
      email: json['email'] as String?,
      isAdmin: json['isAdmin'] as bool? ?? false,
    );
  }
}
