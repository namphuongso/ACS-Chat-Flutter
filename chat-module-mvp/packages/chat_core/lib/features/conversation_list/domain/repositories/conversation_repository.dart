import '../../../../core/domain/entities/chat_member.dart';
import '../entities/conversation.dart';
import '../entities/room_update_type.dart';

abstract class ConversationRepository {
  /// Tạo hoặc lấy lại direct conversation với 1 user khác.
  /// BE tự xử lý duplicate prevention (ACS không có unique constraint
  /// cho direct thread — theo api-docs mục 1.1).
  Future<Conversation> getOrCreateDirectConversation(String otherUserId);

  Future<Conversation> createGroupConversation({
    required List<String> participantIds,
    required String roomName,
    String? avatarUrl,
  });

  Future<List<ChatMember>> getMembers(String roomId);

  Future<List<RoomUpdateType>> getRoomUpdateTypes();

  Future<bool> updateRoomInfo({
    required String roomId,
    required String roomName,
    String? avatarUrl,
    required String roomType,
    String? updateType,
  });

  Future<int> addParticipants({
    required String roomId,
    required List<String> participantIds,
  });

  Future<int> removeParticipants({
    required String roomId,
    required List<String> participantIds,
  });

  Future<bool> transferOwnership({
    required String roomId,
    required String toUserId,
  });

  Future<bool> setRoleAdmin({
    required String roomId,
    required String userId,
    required bool admin,
  });

  Future<bool> leaveRoom({
    required String roomId,
    String? newAdminUserId,
  });

  /// Đóng (khóa) room — giải tán nhóm (API docs mục 23, `close-room`).
  /// Sau khi gọi thành công, BE gửi event `RoomDisbanded` qua realtime
  /// để các thành viên khác cập nhật UI.
  Future<bool> closeRoom({required String roomId});

  Future<String> uploadRoomAvatar({
    required String filePath,
    required String filename,
  });

  Future<String> uploadFileViaSas({
    required String filePath,
    required String fileName,
    String? contentType,
    String? documentId,
    void Function(int sent, int total)? onProgress,
  });

  Future<PaginatedResult<Conversation>> listConversations({
    String? cursor,
    int limit = 20,
  });

  /// Đọc danh sách conversation đã cache local (hiện nhanh khi mở màn hình,
  /// dùng được khi offline). Rỗng nếu chưa có cache.
  Future<List<Conversation>> getCachedConversations();

  Future<Conversation> getConversation(String conversationId);

  /// Ghim/bỏ ghim 1 room (long-press trên danh sách).
  Future<bool> pinConversation(String conversationId, bool pin);
}
