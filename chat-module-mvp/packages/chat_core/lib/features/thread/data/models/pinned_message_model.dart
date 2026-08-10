import '../../domain/entities/pinned_message.dart';

class PinnedMessageModel extends PinnedMessage {
  const PinnedMessageModel({
    required super.messageId,
    required super.content,
    required super.creator,
    required super.createdAt,
    super.type,
    super.attachmentType,
    super.attachmentUrl,
    super.thumbUrl,
  });

  factory PinnedMessageModel.fromJson(Map<String, dynamic> json) {
    return PinnedMessageModel(
      messageId: json['messageId'] as String? ?? '',
      content: json['content'] as String? ?? '',
      creator: json['creator'] as String? ?? '',
      createdAt: _parseDate(json['createdDate'] as String?),
      type: json['type'] as String? ?? '',
      attachmentType: json['attachmentType'] as String? ?? '',
      attachmentUrl: json['attachmentUrl'] as String?,
      thumbUrl: json['thumbUrl'] as String?,
    );
  }

  /// BE trả `createdDate` dạng `dd/MM/yyyy` — parse thủ công (không phụ
  /// thuộc intl). Lỗi format → fallback DateTime.now() để không crash.
  static DateTime _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return DateTime.now();
    final parts = raw.split('/');
    if (parts.length != 3) return DateTime.now();
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return DateTime.now();
    return DateTime(year, month, day);
  }
}
