import 'package:chat_core/chat_core.dart';

/// Helper format preview tin nhắn cuối trong danh sách hội thoại.
class LastMessagePreview {
  /// Chỉ hiện nội dung tin nhắn (bỏ tên người gửi BE đã gộp vào chuỗi).
  /// Nếu người gửi là chính mình thì thêm tiền tố "Bạn: ".
  ///
  /// Cách nhận biết "mình": với room 1-1, tên người còn lại chính là
  /// `roomName` (BE trả tên đối phương) — người gửi khác `roomName`
  /// thì là mình. Không xác định được thì hiện trơn nội dung.
  static String format(Conversation conversation) {
    final summary = conversation.lastMessage;
    if (summary == null) return '';
    final content = summary.content.trim();
    if (content.isEmpty) return '';

    final sender = summary.senderDisplayName.trim();
    if (sender.isEmpty) return content;

    final otherName = conversation.roomName.trim();
    final isMe = otherName.isNotEmpty &&
        sender.toLowerCase() != otherName.toLowerCase();
    return isMe ? 'Bạn: $content' : content;
  }
}
