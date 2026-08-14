import '../../../../core/data/models/chat_member_model.dart';
import '../models/conversation_model.dart';

/// Kết quả phân trang dạng record — datasource chỉ làm việc với Model,
/// không phụ thuộc entity domain.
typedef PaginatedConversations = ({
  List<ConversationModel> items,
  bool hasMore,
  int? nextPageIndex,
});

/// Nguồn dữ liệu conversation từ BE (get-room-chats, conversations/direct...).
abstract class ConversationRemoteDataSource {
  Future<ConversationModel> getOrCreateDirectConversation(String otherUserId);

  Future<ConversationModel> createGroupConversation({
    required List<String> participantIds,
    required String roomName,
    String? avatarUrl,
  });

  Future<List<ChatMemberModel>> getMembers(String roomId);

  Future<bool> updateRoomInfo({
    required String roomId,
    required String roomName,
    String? avatarUrl,
    required String roomType,
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

  Future<bool> leaveRoom({
    required String roomId,
    String? newAdminUserId,
  });

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

  Future<PaginatedConversations> listConversations({
    required int pageIndex,
    int limit = 20,
  });

  Future<ConversationModel> getConversation(String conversationId);

  /// Ghim/bỏ ghim 1 room. Trả về kết quả từ BE (`data: true`).
  Future<bool> pinRoom(String roomId, bool pin);

  void dispose();
}
