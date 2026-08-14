import 'chat_user.dart';

class ChatMember extends ChatUser {
  const ChatMember({
    required super.id,
    required super.displayName,
    super.avatarUrl,
    super.acsUserId,
    super.email,
    this.isAdmin = false,
  });

  final bool isAdmin;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMember && other.id == id && other.isAdmin == isAdmin);

  @override
  int get hashCode => id.hashCode ^ isAdmin.hashCode;
}
