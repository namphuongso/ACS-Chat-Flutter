import '../../../conversation_list/domain/entities/conversation.dart';
import '../models/message_model.dart';
import '../models/pinned_message_model.dart';
import '../models/message_reader_model.dart';
import '../models/message_resource_model.dart';
import '../../domain/entities/message_resource.dart';
import '../../domain/entities/message_reaction.dart';

/// Nguồn dữ liệu tin nhắn: send qua BE (`/chat/send-message`), list/history
/// qua ACS REST, realtime fallback bằng polling.
abstract class MessageRemoteDataSource {
  Future<MessageModel> sendMessage({
    required String roomId,
    required String threadId,
    required String content,
    Map<String, dynamic>? metadata,
  });

  /// Sửa nội dung tin nhắn đã gửi — đi qua BE (`POST /chat/update-message`).
  Future<bool> updateMessage({
    required String roomId,
    String? threadId,
    required String messageId,
    required String content,
    Map<String, dynamic>? metadata,
  });

  /// Xoá tin nhắn — đi qua BE (`POST /chat/delete-message`). ACS không xoá
  /// vật lý mà soft-delete: tin vẫn nằm trong thread với field `deletedOn`.
  Future<bool> deleteMessage({
    required String roomId,
    required String messageId,
  });

  Future<PaginatedResult<MessageModel>> listMessages({
    required String roomId,
    required String threadId,
    String? startTime,
    String? cursor,
  });

  /// Ghim/bỏ ghim 1 tin nhắn — đi qua BE (`POST /chat/pin-message`).
  Future<bool> pinMessage(String messageId, bool pin);

  /// Danh sách tin đang ghim của room — BE
  /// (`GET /chat/get-pinned-messages/{roomId}`). ACS không mang thông tin
  /// ghim, nên đây là nguồn duy nhất để mọi user trong room thấy tin ghim.
  Future<List<PinnedMessageModel>> getPinnedMessages(String roomId);

  Future<List<MessageReaderModel>> getMessageReaders({
    required String roomId,
    required String messageId,
    bool? read,
  });

  Future<PaginatedResult<MessageResourceModel>> getMessageResources({
    required String roomId,
    required MessageResourceType resourceType,
    int pageIndex = 1,
    int pageSize = 50,
    String? keyword,
  });

  Future<List<ReactionConfig>> getReactionConfigs({
    int pageIndex = 1,
    int pageSize = 50,
  });

  Future<List<MessageReaction>> getMessageReactions({
    required String roomId,
    required String messageId,
    int pageIndex = 1,
    int pageSize = 50,
  });

  Future<List<MessageReactionSummary>> getRoomReactions(
    String roomId, {
    int pageIndex = 1,
    int pageSize = 50,
  });

  Future<bool> reactMessage({
    required String roomId,
    required String threadId,
    required String messageId,
    required String reactionCode,
  });

  /// Nhận tin nhắn mới. Bản REST implement bằng polling (Giai đoạn 1).
  /// Gọi lại nhiều lần với cùng threadId phải trả về cùng 1 stream
  /// hoặc broadcast stream — không mở nhiều polling timer song song.
  Stream<MessageModel> watchNewMessages(String roomId, String threadId);

  Future<void> stopWatching(String threadId);

  Future<void> dispose();
}
