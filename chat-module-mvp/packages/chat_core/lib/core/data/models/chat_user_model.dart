import '../../domain/entities/chat_user.dart';

class ChatUserModel extends ChatUser {
  const ChatUserModel({
    required super.id,
    required super.displayName,
    super.avatarUrl,
    super.acsUserId,
    super.email,
  });

  factory ChatUserModel.fromJson(Map<String, dynamic> json) {
    return ChatUserModel(
      id: (json['id'] as String?) ?? (json['userId'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ??
          (json['fullName'] as String?) ??
          (json['contactName'] as String?) ??
          '',
      avatarUrl: (json['avatarUrl'] as String?) ??
          (json['avatar'] as String?) ??
          (json['photoUrl'] as String?) ??
          (json['pictureUrl'] as String?),
      acsUserId: (json['acsUserId'] as String?) ?? (json['cui'] as String?),
      email: json['email'] as String?,
    );
  }
}
