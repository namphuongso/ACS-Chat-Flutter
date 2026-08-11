/// Loại nội dung tin nhắn. Mở rộng (không phải enum cứng) để dễ thêm
/// type mới (vd 'file', 'system') mà không breaking version cũ —
/// theo đúng quyết định "type enum mở" trong kế hoạch gốc mục 7.2.
class MessageType {
  const MessageType._(this.value);
  final String value;

  static const text = MessageType._('text');
  static const html = MessageType._('html');

  /// Fallback an toàn cho type lạ chưa biết (tương thích ngược khi
  /// server trả type mới mà client cũ chưa hỗ trợ).
  static const unknown = MessageType._('unknown');

  static MessageType fromString(String raw) {
    switch (raw) {
      case 'text':
        return text;
      case 'html':
        return html;
      default:
        return unknown;
    }
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is MessageType && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Trạng thái gửi tin — dùng cho optimistic UI (mục "Trạng thái gửi tin"
/// trong roadmap Đợt 1). Chỉ [sending]/[failed] là trạng thái local,
/// [sent] là xác nhận từ ACS.
enum MessageDeliveryStatus { sending, sent, failed }

class Message {
  const Message({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.senderDisplayName,
    required this.content,
    required this.type,
    required this.createdAt,
    this.status = MessageDeliveryStatus.sent,
    this.metadata,
    this.pin = false,
    this.deletedOn,
  });

  final String id;
  final String threadId;
  final String senderId;
  final String senderDisplayName;
  final String content;
  final MessageType type;
  final DateTime createdAt;
  final MessageDeliveryStatus status;
  final bool pin;

  /// Thời điểm tin bị xoá trên ACS (soft-delete). Tin có giá trị này là
  /// đã bị xoá — chỉ field này mới xác định tin bị xoá, KHÔNG dùng
  /// `content` rỗng (tin chỉ có attachment cũng có thể rỗng).
  final DateTime? deletedOn;

  /// Tin đã bị xoá trên ACS (có `deletedOn`). Không hiển thị nữa.
  bool get isDeleted => deletedOn != null;

  /// Dùng cho reply/quote, mention... sau này — để mở sẵn theo mục 7.2
  /// kế hoạch gốc, MVP chưa dùng tới.
  final Map<String, String>? metadata;

  Message copyWith({
    MessageDeliveryStatus? status,
    String? id,
    String? content,
    bool? pin,
    DateTime? deletedOn,
    bool clearDeletedOn = false,
  }) {
    return Message(
      id: id ?? this.id,
      threadId: threadId,
      senderId: senderId,
      senderDisplayName: senderDisplayName,
      content: content ?? this.content,
      type: type,
      createdAt: createdAt,
      status: status ?? this.status,
      metadata: metadata,
      pin: pin ?? this.pin,
      deletedOn: clearDeletedOn
          ? null
          : deletedOn ?? this.deletedOn,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Message && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
