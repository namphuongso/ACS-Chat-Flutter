import '../../domain/entities/message_resource.dart';

class MessageResourceModel extends MessageResource {
  const MessageResourceModel({
    required super.id,
    required super.messageId,
    required super.message,
    required super.createdDate,
    required super.creator,
    required super.resourceType,
    super.thumbUrl,
    super.mediaUrl,
    super.mediaType,
    super.width,
    super.height,
    super.duration,
    super.attachmentUrl,
    super.attachmentType,
    super.linkUrl,
    super.linkTitle,
    super.linkImage,
    super.linkDescription,
    super.linkSource,
  });

  factory MessageResourceModel.fromJson(
    Map<String, dynamic> json,
    MessageResourceType defaultType,
  ) {
    MessageResourceType type = defaultType;
    if (json['mediaUrl'] != null || json['mediaType'] != null) {
      final mediaTypeStr = (json['mediaType'] as String? ?? '').toLowerCase();
      type = mediaTypeStr == 'video'
          ? MessageResourceType.video
          : MessageResourceType.image;
    } else if (json['attachmentUrl'] != null || json['attachmentType'] != null) {
      type = MessageResourceType.file;
    } else if (json['linkUrl'] != null) {
      type = MessageResourceType.link;
    }

    DateTime createdDate;
    if (json['createdDate'] != null) {
      createdDate =
          DateTime.tryParse(json['createdDate'].toString()) ?? DateTime.now();
    } else {
      createdDate = DateTime.now();
    }

    double? duration;
    if (json['duration'] != null) {
      duration = double.tryParse(json['duration'].toString());
    }

    return MessageResourceModel(
      id: (json['id'] ?? '').toString(),
      messageId: (json['messageId'] ?? '').toString(),
      message: (json['message'] ?? json['linkTitle'] ?? '').toString(),
      createdDate: createdDate,
      creator: (json['creator'] ?? '').toString(),
      resourceType: type,
      thumbUrl: json['thumbUrl'] as String?,
      mediaUrl: json['mediaUrl'] as String?,
      mediaType: json['mediaType'] as String?,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      duration: duration,
      attachmentUrl: json['attachmentUrl'] as String?,
      attachmentType: json['attachmentType'] as String?,
      linkUrl: json['linkUrl'] as String?,
      linkTitle: json['linkTitle'] as String?,
      linkImage: json['linkImage'] as String?,
      linkDescription: json['linkDescription'] as String?,
      linkSource: json['linkSource'] as String?,
    );
  }
}
