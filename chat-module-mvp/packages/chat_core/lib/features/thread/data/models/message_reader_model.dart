import '../../domain/entities/message_reader.dart';

class MessageReaderModel extends MessageReader {
  const MessageReaderModel({
    required super.id,
    required super.userId,
    required super.contactName,
    super.avatarUrl,
    super.readTime,
    required super.read,
  });

  factory MessageReaderModel.fromJson(Map<String, dynamic> json) {
    final rawReadTime = json['readTime'] as String?;
    return MessageReaderModel(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      contactName: json['contactName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      readTime: rawReadTime != null ? DateTime.tryParse(rawReadTime) : null,
      read: json['read'] as bool? ?? false,
    );
  }
}
