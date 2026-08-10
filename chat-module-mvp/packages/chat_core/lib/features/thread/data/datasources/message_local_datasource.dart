import '../../domain/entities/message.dart';

/// Lưu trữ tin nhắn local (Hive/SharedPreferences...) để:
/// 1. Load nhanh khi mở thread (cache-first, không phải chờ mạng).
/// 2. Đọc lại được khi offline.
///
/// Không phụ thuộc storage cụ thể — host app tự chọn implement
/// (chat_ui cung cấp bản Hive mặc định).
abstract class MessageLocalDataSource {
  Future<List<Message>> getCachedMessages(String threadId);

  Future<void> saveMessages(String threadId, List<Message> messages);

  Future<void> clear(String threadId);
}
