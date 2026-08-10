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

  Future<PaginatedConversations> listConversations({
    required int pageIndex,
    int limit = 20,
  });

  Future<ConversationModel> getConversation(String conversationId);

  /// Ghim/bỏ ghim 1 room. Trả về kết quả từ BE (`data: true`).
  Future<bool> pinRoom(String roomId, bool pin);

  void dispose();
}
