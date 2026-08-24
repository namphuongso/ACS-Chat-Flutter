import 'package:chat_core/chat_core.dart';
import 'system_message_enricher.dart';

/// Quản lý trạng thái danh sách tin nhắn, sắp xếp theo thời gian,
/// và hỗ trợ các thao tác CRUD (thêm, sửa, xóa, khôi phục từ cache).
class MessageStore {
  const MessageStore({
    required this.enricher,
  });

  final SystemMessageEnricher enricher;

  List<Message> sortChronological(
    List<Message> list, {
    required String roomId,
    required String currentUserId,
    String? myAcsUserId,
  }) {
    final map = <String, Message>{};
    for (final m in list) {
      final enriched = enricher.enrich(
        roomId: roomId,
        message: m,
        currentUserId: currentUserId,
        myAcsUserId: myAcsUserId,
      );

      final key = m.type == MessageType.system
          ? 'sys_${enriched.content.trim()}_${m.createdAt.minute}'
          : m.id;

      if (!map.containsKey(key) ||
          m.createdAt.isAfter(map[key]!.createdAt)) {
        map[key] = enriched;
      }
    }

    final result = map.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  List<Message> appendOrUpdate(
    List<Message> current,
    Message newMessage, {
    required String roomId,
    required String currentUserId,
    String? myAcsUserId,
  }) {
    return sortChronological(
      [...current, newMessage],
      roomId: roomId,
      currentUserId: currentUserId,
      myAcsUserId: myAcsUserId,
    );
  }

  List<Message> removeById(List<Message> current, String messageId) {
    return current.where((m) => m.id != messageId).toList();
  }

  List<Message> updateById(
    List<Message> current,
    String messageId,
    Message Function(Message oldMessage) updateFn,
  ) {
    return current.map((m) => m.id == messageId ? updateFn(m) : m).toList();
  }
}
