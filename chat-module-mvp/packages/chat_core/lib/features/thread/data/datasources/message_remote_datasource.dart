import '../../../conversation_list/domain/entities/conversation.dart';
import '../models/message_model.dart';
import '../models/pinned_message_model.dart';

/// Nguồn dữ liệu tin nhắn: send qua BE (`/chat/send-message`), list/history
/// qua ACS REST, realtime fallback bằng polling.
abstract class MessageRemoteDataSource {
  Future<MessageModel> sendMessage({
    required String roomId,
    required String threadId,
    required String content,
  });

  /// Sửa nội dung tin nhắn đã gửi — đi qua BE (`POST /chat/update-message`).
  Future<bool> updateMessage({
    required String roomId,
    required String messageId,
    required String content,
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

  /// Nhận tin nhắn mới. Bản REST implement bằng polling (Giai đoạn 1).
  /// Gọi lại nhiều lần với cùng threadId phải trả về cùng 1 stream
  /// hoặc broadcast stream — không mở nhiều polling timer song song.
  Stream<MessageModel> watchNewMessages(String roomId, String threadId);

  Future<void> stopWatching(String threadId);

  Future<void> dispose();
}
