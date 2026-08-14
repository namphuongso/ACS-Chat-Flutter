import '../../../../core/data/models/chat_member_model.dart';
import '../../domain/entities/chat_access_token.dart';

class ChatAccessTokenModel extends ChatAccessToken {
  const ChatAccessTokenModel({
    required super.token,
    required super.expiresOn,
    required super.acsUserId,
    super.participants = const [],
  });

  factory ChatAccessTokenModel.fromJson(Map<String, dynamic> json) {
    final membersJson = json['members'] as List?;
    final members = membersJson != null
        ? membersJson
            .whereType<Map>()
            .map((m) => ChatMemberModel.fromJson(m.cast<String, dynamic>()))
            .toList()
        : const <ChatMemberModel>[];

    return ChatAccessTokenModel(
      token: json['token'] as String,
      expiresOn: DateTime.parse(json['tokenUtcExp'] as String),
      acsUserId: json['cui'] as String,
      participants: members,
    );
  }
}
