import '../../../../core/domain/entities/chat_user.dart';

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
}

class Conversation {
  const Conversation({
    required this.id,
    required this.threadId,
    required this.type,
    required this.participants,
    required this.createdAt,
    required this.updatedAt,
    this.roomName = '',
    this.avatarUrl,
    this.pid,
    this.pin = false,
    this.isMuted = false,
    this.unreadCount = 0,
    this.lastMessage,
    this.token,
    this.tokenUtcExp,
    this.cui,
  });

  /// Backend conversation ID (không phải ACS threadId) — dùng để gọi
  /// các endpoint BE (`/api/chat/...`).
  final String id;

  /// ACS thread ID — dùng để gọi ACS REST trực tiếp (send/list message).
  final String threadId;

  final ConversationType type;
  final List<ChatUser> participants;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Tên hiển thị của room do BE trả về (room 1-1 thường là tên đối phương).
  final String roomName;

  /// Ảnh đại diện của room (có thể rỗng nếu BE không trả).
  final String? avatarUrl;

  /// Id người còn lại trong room 1-1 (partner id trên BE NPP).
  final String? pid;

  /// Room có được ghim hay không.
  final bool pin;

  /// Room có bị tắt thông báo hay không.
  final bool isMuted;

  final int unreadCount;
  final ConversationSummary? lastMessage;

  /// Token cấp kèm khi tạo/join room để cache trực tiếp.
  final String? token;
  final DateTime? tokenUtcExp;
  final String? cui;

  Conversation copyWith({
    bool? pin,
    bool? isMuted,
    int? unreadCount,
    ConversationSummary? lastMessage,
    List<ChatUser>? participants,
  }) {
    return Conversation(
      id: id,
      threadId: threadId,
      type: type,
      participants: participants ?? this.participants,
      createdAt: createdAt,
      updatedAt: updatedAt,
      roomName: roomName,
      avatarUrl: avatarUrl,
      pid: pid,
      pin: pin ?? this.pin,
      isMuted: isMuted ?? this.isMuted,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessage: lastMessage ?? this.lastMessage,
      token: token,
      tokenUtcExp: tokenUtcExp,
      cui: cui,
    );
  }
}

class PaginatedResult<T> {
  const PaginatedResult(
      {required this.items, required this.hasMore, this.cursor});
  final List<T> items;
  final bool hasMore;
  final String? cursor;
}
