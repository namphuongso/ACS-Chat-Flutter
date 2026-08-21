class MessageReader {
  const MessageReader({
    required this.id,
    required this.userId,
    required this.contactName,
    this.avatarUrl,
    this.readTime,
    required this.read,
  });

  final String id;
  final String userId;
  final String contactName;
  final String? avatarUrl;
  final DateTime? readTime;
  final bool read;
}
