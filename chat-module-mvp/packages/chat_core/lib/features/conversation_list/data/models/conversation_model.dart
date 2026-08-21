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
    if (json is! Map) return null;
    final map = json.cast<String, dynamic>();
    final createdStr = map['createdAt']?.toString() ?? '';
    final createdAt = DateTime.tryParse(createdStr)?.toLocal() ?? DateTime.now();
    return ConversationSummaryModel(
      content: map['content']?.toString() ?? '',
      senderDisplayName:
          (map['sender'] as Map<String, dynamic>?)?['displayName']?.toString() ??
              '',
      senderId: (map['sender'] as Map<String, dynamic>?)?['id']?.toString() ??
          (map['sender'] as Map<String, dynamic>?)?['acsUserId']?.toString(),
      createdAt: createdAt,
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
    final createdStr = json['created']?.toString() ?? '';
    final createdAt = DateTime.tryParse(createdStr)?.toLocal() ?? DateTime.now();
    final modifiedStr = json['modified']?.toString();
    final updatedAt = modifiedStr != null
        ? (DateTime.tryParse(modifiedStr)?.toLocal() ?? createdAt)
        : createdAt;

    final lastMessageTimeStr = json['lastMessageTime']?.toString();
    final lastMessageTime = lastMessageTimeStr != null
        ? (DateTime.tryParse(lastMessageTimeStr)?.toLocal() ?? createdAt)
        : createdAt;

    return ConversationModel(
      id: json['id']?.toString() ?? '',
      threadId: json['threadId']?.toString() ?? '',
      type: json['type'] == 'group' || json['type'] == 'G'
          ? ConversationType.group
          : ConversationType.direct,
      participants: ((json['participants'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => ChatUserModel.fromJson(e.cast<String, dynamic>()))
          .toList(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      roomName: json['roomName']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString(),
      pid: json['pid']?.toString(),
      pin: json['pin'] as bool? ?? false,
      isMuted: json['isMuted'] as bool? ?? false,
      unreadCount: (json['isRead'] as bool? ?? true) ? 0 : 1,
      lastMessage: json['lastMessage'] != null &&
              (json['lastMessage'].toString()).isNotEmpty
          ? _summaryFromRaw(
              raw: json['lastMessage'].toString(),
              createdAt: lastMessageTime,
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
