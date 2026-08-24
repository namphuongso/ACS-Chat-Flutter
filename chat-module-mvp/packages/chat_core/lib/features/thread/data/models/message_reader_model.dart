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
    final rawReadTime = json['readTime'] as String? ??
        json['readTimeUtc'] as String? ??
        json['readAt'] as String? ??
        json['updatedAt'] as String? ??
        json['createdAt'] as String?;

    final name = json['contactName']?.toString() ??
        json['displayName']?.toString() ??
        json['userName']?.toString() ??
        json['name']?.toString() ??
        json['fullName']?.toString() ??
        '';

    final userId = json['userId']?.toString() ??
        json['actorId']?.toString() ??
        json['readerId']?.toString() ??
        json['id']?.toString() ??
        '';

    final avatar = json['avatarUrl']?.toString() ??
        json['avatar']?.toString() ??
        json['userAvatarUrl']?.toString();

    final isRead = json['read'] as bool? ??
        json['isRead'] as bool? ??
        json['hasRead'] as bool? ??
        (rawReadTime != null);

    return MessageReaderModel(
      id: json['id']?.toString() ?? userId,
      userId: userId,
      contactName: name,
      avatarUrl: avatar,
      readTime: rawReadTime != null ? DateTime.tryParse(rawReadTime) : null,
      read: isRead,
    );
  }
}
