/// Tin nhắn được ghim trong room — lấy từ BE
/// `GET /api/chat/get-pinned-messages/{roomId}` (ACS không mang thông tin
/// ghim, đây là business logic phía NPP).
class PinnedMessage {
  const PinnedMessage({
    required this.messageId,
    required this.content,
    required this.creator,
    required this.createdAt,
    this.type = '',
    this.attachmentType = '',
    this.attachmentUrl,
    this.thumbUrl,
  });

  final String messageId;

  /// Nội dung tin nhắn.
  final String content;

  /// Tên người gửi (BE trả ở field `creator`).
  final String creator;

  /// Thời gian gửi (BE trả `createdDate` dạng `dd/MM/yyyy`, parse về
  /// DateTime — chỉ có ngày, giờ = 00:00).
  final DateTime createdAt;

  final String type;
  final String attachmentType;
  final String? attachmentUrl;
  final String? thumbUrl;
}
