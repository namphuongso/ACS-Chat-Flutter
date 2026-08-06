import '../../conversation_list/domain/conversation.dart'; // Để dùng PaginatedResult
import 'message.dart';

abstract class MessageRepository {
  /// Gửi tin nhắn — gọi thẳng ACS REST (không qua BE, theo mục 4 kế hoạch gốc).
  Future<Message> sendMessage({
    required String threadId,
    required String content,
  });

  /// Load lịch sử / pagination — gọi thẳng ACS REST `listMessages`.
  /// [startTime] dùng để tránh lấy nguyên trang mỗi lần (mục 5 kế hoạch gốc).
  Future<PaginatedResult<Message>> listMessages({
    required String threadId,
    String? startTime,
    String? cursor,
  });

  /// Nhận tin nhắn mới. Bản REST implement bằng polling (Giai đoạn 1,
  /// KHÔNG đạt UX Messenger/Zalo — chỉ dùng bước đệm). Bản native
  /// implement qua EventChannel (Giai đoạn 2).
  ///
  /// Gọi lại nhiều lần với cùng threadId phải trả về cùng 1 stream
  /// hoặc broadcast stream — không mở nhiều polling timer song song
  /// cho cùng 1 thread.
  Stream<Message> watchNewMessages(String threadId);

  /// Dừng mọi kết nối/timer đang chạy cho threadId này (gọi khi rời
  /// màn hình thread hoặc app vào background — theo mục 5 kế hoạch gốc:
  /// "chỉ poll đúng 1 thread đang mở, dừng hẳn khi app vào background").
  Future<void> stopWatching(String threadId);
}
