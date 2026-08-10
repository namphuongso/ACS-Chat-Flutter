import '../entities/conversation.dart';

abstract class ConversationRepository {
  /// Tạo hoặc lấy lại direct conversation với 1 user khác.
  /// BE tự xử lý duplicate prevention (ACS không có unique constraint
  /// cho direct thread — theo api-docs mục 1.1).
  Future<Conversation> getOrCreateDirectConversation(String otherUserId);

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
