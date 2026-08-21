enum MessageResourceType {
  image('Image'),
  video('Video'),
  file('File'),
  link('Link');

  const MessageResourceType(this.value);
  final String value;

  static MessageResourceType fromString(String? raw) {
    if (raw == null) return MessageResourceType.file;
    final clean = raw.trim().toLowerCase();
    if (clean == 'image') return MessageResourceType.image;
    if (clean == 'video') return MessageResourceType.video;
    if (clean == 'file') return MessageResourceType.file;
    if (clean == 'link') return MessageResourceType.link;
    return MessageResourceType.file;
  }
}

class MessageResource {
  const MessageResource({
    required this.id,
    required this.messageId,
    required this.message,
    required this.createdDate,
    required this.creator,
    required this.resourceType,
    this.thumbUrl,
    this.mediaUrl,
    this.mediaType,
    this.width,
    this.height,
    this.duration,
    this.attachmentUrl,
    this.attachmentType,
    this.linkUrl,
    this.linkTitle,
    this.linkImage,
    this.linkDescription,
    this.linkSource,
  });

  final String id;
  final String messageId;
  final String message;
  final DateTime createdDate;
  final String creator;
  final MessageResourceType resourceType;

  final String? thumbUrl;
  final String? mediaUrl;
  final String? mediaType;
  final int? width;
  final int? height;
  final double? duration;

  final String? attachmentUrl;
  final String? attachmentType;

  final String? linkUrl;
  final String? linkTitle;
  final String? linkImage;
  final String? linkDescription;
  final String? linkSource;
}
