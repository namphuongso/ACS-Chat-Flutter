import '../../domain/entities/conversation.dart';

/// Lưu trữ danh sách conversation local (Hive/SharedPreferences...) để:
/// 1. Hiện danh sách ngay khi mở màn hình (cache-first).
/// 2. Đọc lại được khi offline.
abstract class ConversationLocalDataSource {
  Future<List<Conversation>> getCachedConversations();

  Future<void> saveConversations(List<Conversation> conversations);

  Future<void> clear();
}
