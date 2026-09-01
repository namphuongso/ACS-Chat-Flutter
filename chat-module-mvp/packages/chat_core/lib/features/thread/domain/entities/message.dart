/// Loại nội dung tin nhắn. Mở rộng (không phải enum cứng) để dễ thêm
/// type mới (vd 'file', 'system') mà không breaking version cũ —
/// theo đúng quyết định "type enum mở" trong kế hoạch gốc mục 7.2.
class MessageType {
  const MessageType._(this.value);
  final String value;

  static const text = MessageType._('text');
  static const html = MessageType._('html');
  static const system = MessageType._('system');
  static const reactionUpdate = MessageType._('reactionUpdate');
  static const messagePinUpdate = MessageType._('messagePinUpdate');
  static const roomDisbanded = MessageType._('roomDisbanded');
  static const roomPinnedUpdate = MessageType._('roomPinnedUpdate');
  static const roomUnpinnedUpdate = MessageType._('roomUnpinnedUpdate');
  static const roomUpdatedUpdate = MessageType._('roomUpdatedUpdate');
  static const memberJoinedUpdate = MessageType._('memberJoinedUpdate');
  static const memberLeftUpdate = MessageType._('memberLeftUpdate');
  static const memberRemovedUpdate = MessageType._('memberRemovedUpdate');
  static const memberRemovedSelf = MessageType._('memberRemovedSelf');

  /// Fallback an toàn cho type lạ chưa biết (tương thích ngược khi
  /// server trả type mới mà client cũ chưa hỗ trợ).
  static const unknown = MessageType._('unknown');

  static MessageType fromString(String raw) {
    switch (raw) {
      case 'text':
        return text;
      case 'html':
        return html;
      case 'system':
      case 'participantAdded':
      case 'participantRemoved':
      case 'topicUpdated':
        return system;
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
  static const String deletedContentPlaceholder = 'Tin nhắn đã bị xoá';

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

  /// Tin đã bị xoá trên ACS. Chỉ dùng `deletedOn` để tránh false-positive
  /// với tin nhắn hợp lệ có nội dung giống placeholder.
  bool get isDeleted => deletedOn != null;

  /// Nội dung hiển thị cho bubble chat.
  String get displayContent => isDeleted ? deletedContentPlaceholder : content;

  /// Metadata chứa thông tin hình ảnh, tệp, video, link, html...
  final Map<String, dynamic>? metadata;

  Message copyWith({
    MessageDeliveryStatus? status,
    String? id,
    String? content,
    bool? pin,
    DateTime? deletedOn,
    bool clearDeletedOn = false,
    Map<String, dynamic>? metadata,
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
      metadata: metadata ?? this.metadata,
      pin: pin ?? this.pin,
      deletedOn: clearDeletedOn ? null : deletedOn ?? this.deletedOn,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.runtimeType == runtimeType &&
          other.id == id &&
          other.content == content &&
          other.status == status &&
          other.pin == pin &&
          other.deletedOn == deletedOn &&
          _mapEquals(other.metadata, metadata));

  @override
  int get hashCode => Object.hash(
        id,
        content,
        status,
        pin,
        deletedOn,
        metadata != null ? Object.hashAll(metadata!.entries) : null,
      );
}

bool _mapEquals(Map<dynamic, dynamic>? a, Map<dynamic, dynamic>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || b[key] != a[key]) return false;
  }
  return true;
}
