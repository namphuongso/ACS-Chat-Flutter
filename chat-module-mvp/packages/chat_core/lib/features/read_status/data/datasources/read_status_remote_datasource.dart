/// Nguồn dữ liệu đánh dấu đã đọc từ BE (`POST /conversations/:id/read`).
abstract class ReadStatusRemoteDataSource {
  Future<void> markAsRead(String conversationId);

  void dispose();
}
