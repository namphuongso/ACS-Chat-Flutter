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
  });

  factory MessageModel.fromAcsJson(Map<String, dynamic> json,
      {required String threadId}) {
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
      content: json['content'] is Map
          ? (json['content'] as Map<String, dynamic>)['message'] as String? ??
              ''
          : json['content'] as String? ?? '',
      type: MessageType.fromString(json['type'] as String? ?? 'text'),
      createdAt: DateTime.parse(json['createdOn'] as String? ??
          json['createdAt'] as String? ??
          DateTime.now().toIso8601String()),
      metadata: (json['metadata'] as Map?)?.cast<String, String>(),
    );
  }
}
