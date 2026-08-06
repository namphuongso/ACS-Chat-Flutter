import 'conversation.dart';

abstract class ConversationRepository {
  /// Tạo hoặc lấy lại direct conversation với 1 user khác.
  /// BE tự xử lý duplicate prevention (ACS không có unique constraint
  /// cho direct thread — theo api-docs mục 1.1).
  Future<Conversation> getOrCreateDirectConversation(String otherUserId);

  Future<PaginatedResult<Conversation>> listConversations({
    String? cursor,
    int limit = 20,
  });

  Future<Conversation> getConversation(String conversationId);
}
