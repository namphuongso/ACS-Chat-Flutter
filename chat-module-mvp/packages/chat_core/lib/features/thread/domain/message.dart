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
  });

  final String id;
  final String threadId;
  final String senderId;
  final String senderDisplayName;
  final String content;
  final MessageType type;
  final DateTime createdAt;
  final MessageDeliveryStatus status;

  /// Dùng cho reply/quote, mention... sau này — để mở sẵn theo mục 7.2
  /// kế hoạch gốc, MVP chưa dùng tới.
  final Map<String, String>? metadata;

  Message copyWith({MessageDeliveryStatus? status, String? id}) {
    return Message(
      id: id ?? this.id,
      threadId: threadId,
      senderId: senderId,
      senderDisplayName: senderDisplayName,
      content: content,
      type: type,
      createdAt: createdAt,
      status: status ?? this.status,
      metadata: metadata,
    );
  }

  // TODO(verify-acs-schema): field name ở đây (sender, content.message,
  // createdOn) dựa theo cấu trúc ACS Chat REST API mà mình nắm được,
  // NHƯNG chưa test được với response thật (sandbox không gọi được ACS).
  // Việc đầu tiên khi có access thật: gọi thử 1 request `listMessages`,
  // log raw JSON, đối chiếu lại đúng field trước khi tin tưởng mapper này.
  factory Message.fromAcsJson(Map<String, dynamic> json, {required String threadId}) {
    final sender = json['senderDisplayName'] as String? ?? 'Unknown';
    return Message(
      id: json['id'] as String,
      threadId: threadId,
      senderId: (json['sender'] as Map<String, dynamic>?)?['communicationIdentifier']
              ?.toString() ??
          json['senderId'] as String? ??
          '',
      senderDisplayName: sender,
      content: json['content'] is Map
          ? (json['content'] as Map<String, dynamic>)['message'] as String? ?? ''
          : json['content'] as String? ?? '',
      type: MessageType.fromString(json['type'] as String? ?? 'text'),
      createdAt: DateTime.parse(json['createdOn'] as String? ??
          json['createdAt'] as String? ??
          DateTime.now().toIso8601String()),
      metadata: (json['metadata'] as Map?)?.cast<String, String>(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Message && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
