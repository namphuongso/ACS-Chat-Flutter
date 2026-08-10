import '../../../../core/data/models/chat_user_model.dart';
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
            .map((m) => ChatUserModel.fromJson(m as Map<String, dynamic>))
            .toList()
        : const <ChatUserModel>[];

    return ChatAccessTokenModel(
      token: json['token'] as String,
      expiresOn: DateTime.parse(json['tokenUtcExp'] as String),
      acsUserId: json['cui'] as String,
      participants: members,
    );
  }
}
