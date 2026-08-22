import '../../../conversation_list/domain/entities/conversation.dart';
import '../entities/message.dart';
import '../entities/pinned_message.dart';
import '../entities/message_reader.dart';
import '../entities/message_resource.dart';
import '../entities/message_reaction.dart';

abstract class MessageRepository {
  /// Gửi tin nhắn — đi qua BE (`POST /chat/send-message`), BE chịu trách
  /// nhiệm ghi vào ACS.
  Future<Message> sendMessage({
    required String roomId,
    required String threadId,
    required String content,
    Map<String, dynamic>? metaData,
  });

  /// Sửa nội dung tin nhắn đã gửi — đi qua BE (`POST /chat/update-message`).
  /// Chỉ chủ nhân tin nhắn mới được sửa.
  Future<bool> updateMessage({
    required String roomId,
    required String threadId,
    required String messageId,
    required String content,
    Map<String, dynamic>? metadata,
  });

  /// Xoá tin nhắn — đi qua BE (`POST /chat/delete-message`). ACS soft-delete
  /// (gắn `deletedOn`) nên tin sẽ bị ẩn ở các lần load sau.
  Future<bool> deleteMessage({
    required String roomId,
    required String threadId,
    required String messageId,
  });

  /// Load lịch sử / pagination — gọi thẳng ACS REST `listMessages`.
  /// [startTime] dùng để tránh lấy nguyên trang mỗi lần (mục 5 kế hoạch gốc).
  Future<PaginatedResult<Message>> listMessages({
    required String roomId,
    required String threadId,
    String? startTime,
    String? cursor,
  });

  /// Đọc tin nhắn đã cache local (đọc trước khi mở thread để hiện ngay,
  /// dùng được khi offline). Rỗng nếu chưa có cache.
  Future<List<Message>> getCachedMessages(String threadId);

  /// Ghim/bỏ ghim 1 tin nhắn (long-press trên tin nhắn).
  Future<bool> pinMessage({
    required String threadId,
    required String messageId,
    required bool pin,
  });

  /// Danh sách tin đang ghim của room — BE. Mọi user trong room cùng nhìn
  /// thấy tin ghim (ACS không mang thông tin này).
  Future<List<PinnedMessage>> getPinnedMessages(String roomId);

  Future<List<MessageReader>> getMessageReaders({
    required String roomId,
    required String messageId,
    bool? read,
  });

  Future<PaginatedResult<MessageResource>> getMessageResources({
    required String roomId,
    required MessageResourceType resourceType,
    int pageIndex = 1,
    int pageSize = 50,
    String? keyword,
  });

  Future<List<ReactionConfig>> getReactionConfigs();

  Future<List<MessageReaction>> getMessageReactions({
    required String roomId,
    required String messageId,
  });

  Future<List<MessageReactionSummary>> getRoomReactions(String roomId);

  Future<bool> reactMessage({
    required String roomId,
    required String threadId,
    required String messageId,
    required String reactionCode,
  });

  /// Nhận tin nhắn mới. Bản REST implement bằng polling (Giai đoạn 1,
  /// KHÔNG đạt UX Messenger/Zalo — chỉ dùng bước đệm). Bản native
  /// implement qua EventChannel (Giai đoạn 2).
  ///
  /// Gọi lại nhiều lần với cùng threadId phải trả về cùng 1 stream
  /// hoặc broadcast stream — không mở nhiều polling timer song song
  /// cho cùng 1 thread.
  Stream<Message> watchNewMessages(String roomId, String threadId);

  /// Dừng mọi kết nối/timer đang chạy cho threadId này (gọi khi rời
  /// màn hình thread hoặc app vào background — theo mục 5 kế hoạch gốc:
  /// "chỉ poll đúng 1 thread đang mở, dừng hẳn khi app vào background").
  Future<void> stopWatching(String threadId);

  /// Nhận tin mới cho toàn bộ danh sách hội thoại — realtime native
  /// client-level, KHÔNG cần mở thread. [roomId] dùng để lấy ACS token.
  /// Gọi nhiều lần phải trả về cùng 1 broadcast stream.
  Stream<Message> watchListMessages();

  /// Dừng realtime cho danh sách hội thoại.
  Future<void> stopWatchingList();

  /// Gửi WebSocket `read` payload với lastVisibleMessageId theo giao thức backend.
  void sendReadMessage(String lastVisibleMessageId, {String? roomId});

  /// Xoá trạng thái lastVisibleMessageId để không gửi nhầm read khi ở ngoài room hoặc background.
  void clearReadMessageState();

  /// Gửi sự kiện leave_room WebSocket khi người dùng chuyển sang màn hình chi tiết, sang tab khác hoặc background.
  void leaveActiveRoom();
}
