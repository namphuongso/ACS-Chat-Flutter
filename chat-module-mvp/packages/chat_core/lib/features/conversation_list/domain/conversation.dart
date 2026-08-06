import '../../shared/chat_user.dart';

/// MVP chỉ dùng [direct]. [group] để sẵn enum cho Đợt 1 roadmap sau MVP,
/// KHÔNG implement logic group ở bản này.
enum ConversationType { direct, group }

class ConversationSummary {
  const ConversationSummary({
    required this.content,
    required this.senderDisplayName,
    required this.createdAt,
  });

  final String content;
  final String senderDisplayName;
  final DateTime createdAt;

  static ConversationSummary? fromJsonNullable(dynamic json) {
    if (json == null) return null;
    final map = json as Map<String, dynamic>;
    return ConversationSummary(
      content: map['content'] as String? ?? '',
      senderDisplayName:
          (map['sender'] as Map<String, dynamic>?)?['displayName'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

class Conversation {
  const Conversation({
    required this.id,
    required this.threadId,
    required this.type,
    required this.participants,
    required this.createdAt,
    required this.updatedAt,
    this.unreadCount = 0,
    this.lastMessage,
  });

  /// Backend conversation ID (không phải ACS threadId) — dùng để gọi
  /// các endpoint BE (`/api/conversations/:id/...`).
  final String id;

  /// ACS thread ID — dùng để gọi ACS REST trực tiếp (send/list message).
  final String threadId;

  final ConversationType type;
  final List<ChatUser> participants;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int unreadCount;
  final ConversationSummary? lastMessage;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      threadId: json['threadId'] as String,
      type: json['type'] == 'group' ? ConversationType.group : ConversationType.direct,
      participants: ((json['participants'] as List?) ?? [])
          .map((e) => ChatUser.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      unreadCount: json['unreadCount'] as int? ?? 0,
      lastMessage: ConversationSummary.fromJsonNullable(json['lastMessage']),
    );
  }
}

class PaginatedResult<T> {
  const PaginatedResult({required this.items, required this.hasMore, this.cursor});
  final List<T> items;
  final bool hasMore;
  final String? cursor;
}
