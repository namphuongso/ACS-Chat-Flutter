import '../../../../core/data/models/chat_member_model.dart';
import '../../../../core/data/models/chat_user_model.dart';
import '../../domain/entities/conversation.dart';

class ConversationSummaryModel extends ConversationSummary {
  const ConversationSummaryModel({
    required super.content,
    required super.senderDisplayName,
    required super.createdAt,
    super.senderId,
  });

  static ConversationSummaryModel? fromJsonNullable(dynamic json) {
    if (json == null) return null;
    final map = json as Map<String, dynamic>;
    return ConversationSummaryModel(
      content: map['content'] as String? ?? '',
      senderDisplayName:
          (map['sender'] as Map<String, dynamic>?)?['displayName'] as String? ??
              '',
      senderId: (map['sender'] as Map<String, dynamic>?)?['id'] as String? ??
          (map['sender'] as Map<String, dynamic>?)?['acsUserId'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String).toLocal(),
    );
  }
}

class ConversationModel extends Conversation {
  const ConversationModel({
    required super.id,
    required super.threadId,
    required super.type,
    required super.participants,
    required super.createdAt,
    required super.updatedAt,
    super.roomName,
    super.avatarUrl,
    super.pid,
    super.pin,
    super.isMuted,
    super.unreadCount = 0,
    super.lastMessage,
    super.token,
    super.tokenUtcExp,
    super.cui,
  });

  /// Parse item trả về từ `GET /chat/get-room-chats`.
  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] as String,
      threadId: json['threadId'] as String,
      type: json['type'] == 'group' || json['type'] == 'G'
          ? ConversationType.group
          : ConversationType.direct,
      participants: ((json['participants'] as List?) ?? [])
          .map((e) => ChatUserModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created'] as String).toLocal(),
      updatedAt: json['modified'] != null
          ? DateTime.parse(json['modified'] as String).toLocal()
          : DateTime.parse(json['created'] as String).toLocal(),
      roomName: json['roomName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      pid: json['pid'] as String?,
      pin: json['pin'] as bool? ?? false,
      isMuted: json['isMuted'] as bool? ?? false,
      unreadCount: (json['isRead'] as bool? ?? true) ? 0 : 1,
      lastMessage: json['lastMessage'] != null &&
              (json['lastMessage'] as String).isNotEmpty
          ? _summaryFromRaw(
              raw: json['lastMessage'] as String,
              createdAt: json['lastMessageTime'] != null
                  ? DateTime.parse(json['lastMessageTime'] as String).toLocal()
                  : DateTime.parse(json['created'] as String).toLocal(),
            )
          : null,
    );
  }

  /// Giữ nguyên chuỗi `lastMessage` do BE trả về để UI hiển thị đúng dữ liệu.
  static ConversationSummaryModel _summaryFromRaw({
    required String raw,
    required DateTime createdAt,
  }) {
    return ConversationSummaryModel(
      content: raw,
      senderDisplayName: '',
      createdAt: createdAt,
    );
  }

  /// Parse response của `POST /chat/create-room` hoặc
  /// `POST /chat/join-room/{roomId}` — schema khác `get-room-chats`
  /// (dùng `roomId`/`roomType`, có `members`, kèm `cui`/`token`/`tokenUtcExp`).
  factory ConversationModel.fromRoomJson(Map<String, dynamic> json) {
    final members = ((json['members'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => ChatMemberModel.fromJson(e.cast<String, dynamic>()))
        .toList();
    final created = DateTime.now();
    return ConversationModel(
      id: json['roomId'] as String,
      threadId: json['threadId'] as String,
      type: json['roomType'] == 'U'
          ? ConversationType.direct
          : ConversationType.group,
      participants: members,
      createdAt: created,
      updatedAt: created,
      roomName: json['roomName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      pid: json['pid'] as String?,
      token: json['token'] as String?,
      tokenUtcExp: json['tokenUtcExp'] != null
          ? DateTime.parse(json['tokenUtcExp'] as String)
          : null,
      cui: json['cui'] as String?,
    );
  }
}
