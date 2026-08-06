abstract class ReadStatusRepository {
  /// Đánh dấu đã đọc — qua BE (`POST /conversations/:id/read`).
  Future<void> markAsRead(String conversationId);
}
