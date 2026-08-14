import 'dart:convert';

import '../../domain/entities/message.dart';

class MessageModel extends Message {
  const MessageModel({
    required super.id,
    required super.threadId,
    required super.senderId,
    required super.senderDisplayName,
    required super.content,
    required super.type,
    required super.createdAt,
    super.status = MessageDeliveryStatus.sent,
    super.metadata,
    super.pin = false,
    super.deletedOn,
  });

  factory MessageModel.fromAcsJson(Map<String, dynamic> json,
      {required String threadId}) {
    final rawType = json['type'] as String? ?? 'text';
    final sender = json['senderDisplayName'] as String? ?? 'Unknown';
    final senderMap =
        json['senderCommunicationIdentifier'] as Map<String, dynamic>?;
    final senderId = senderMap?['rawId']?.toString() ??
        (json['sender'] as Map<String, dynamic>?)?['communicationIdentifier']
            ?.toString() ??
        json['senderId'] as String? ??
        '';

    return MessageModel(
      id: json['id'] as String,
      threadId: threadId,
      senderId: senderId,
      senderDisplayName: sender,
      content: _contentFromAcsJson(json, rawType),
      type: MessageType.fromString(rawType),
      createdAt: DateTime.parse(json['createdOn'] as String? ??
              json['createdAt'] as String? ??
              DateTime.now().toIso8601String())
          .toLocal(),
      deletedOn: json['deletedOn'] != null
          ? DateTime.parse(json['deletedOn'] as String).toLocal()
          : null,
      metadata: _metadataFromJson(
          json['metadata'] ?? json['metaData'] ?? json['Metadata']),
    );
  }

  /// Payload realtime của backend hiện dùng PascalCase và không bọc trong
  /// object `content` giống API get-messages.
  factory MessageModel.fromWebSocketJson(
    Map<String, dynamic> json, {
    required String threadId,
  }) {
    final deletedOn = json['DeletedDate'] ?? json['deletedDate'];
    return MessageModel(
      id: (json['MessageId'] ?? json['messageId'] ?? json['id']).toString(),
      threadId: threadId,
      senderId:
          (json['SenderId'] ?? json['senderId'] ?? '').toString(),
      senderDisplayName:
          (json['SenderName'] ?? json['senderName'] ?? '').toString(),
      content: (json['Content'] ?? json['content'] ?? '').toString(),
      type: MessageType.fromString(
        (json['Type'] ?? json['type'] ?? 'text').toString(),
      ),
      createdAt: DateTime.tryParse(
                (json['CreatedDate'] ?? json['createdDate'] ?? '').toString(),
              )?.toLocal() ??
          DateTime.now(),
      deletedOn: deletedOn == null
          ? null
          : DateTime.tryParse(deletedOn.toString())?.toLocal(),
      metadata: _metadataFromJson(json['Metadata'] ??
          json['metadata'] ??
          json['MetaData'] ??
          json['metaData']),
    );
  }

  static Map<String, dynamic>? _metadataFromJson(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      if (raw.isEmpty) return null;
      return raw.cast<String, dynamic>();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded.isNotEmpty) {
          return decoded.cast<String, dynamic>();
        }
      } catch (_) {}
    }
    return null;
  }

  static String _contentFromAcsJson(Map<String, dynamic> json, String rawType) {
    final content = json['content'];
    if (content is! Map) return content as String? ?? '';
    final map = content.cast<String, dynamic>();

    if (rawType == 'participantAdded' || rawType == 'participantRemoved') {
      final names = (map['participants'] as List? ?? const [])
          .whereType<Map>()
          .map((participant) => participant['displayName']?.toString().trim())
          .whereType<String>()
          .where((name) => name.isNotEmpty)
          .toList();
      if (names.isEmpty) {
        return rawType == 'participantAdded'
            ? 'Đã thêm thành viên vào nhóm'
            : 'Đã xóa thành viên khỏi nhóm';
      }
      final joinedNames = names.join(', ');
      return rawType == 'participantAdded'
          ? '**$joinedNames** đã được thêm vào nhóm'
          : '**$joinedNames** đã bị xóa khỏi nhóm';
    }

    if (rawType == 'topicUpdated') {
      final topic = map['topic']?.toString().trim() ?? '';
      return topic.isEmpty
          ? 'Tên nhóm đã được cập nhật'
          : 'Tên nhóm đã được đổi thành "**$topic**"';
    }

    return map['message'] as String? ?? '';
  }
}
