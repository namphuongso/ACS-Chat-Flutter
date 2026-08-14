class ReactionConfig {
  const ReactionConfig({
    this.id,
    required this.code,
    required this.displayName,
    required this.iconUrl,
  });

  final String? id;
  final String code;
  final String displayName;
  final String iconUrl;
}

class MessageReaction {
  const MessageReaction({
    required this.userId,
    required this.contactName,
    required this.reactionCode,
    required this.reactionIconUrl,
    this.avatarUrl,
    this.reactedAt,
  });

  final String userId;
  final String contactName;
  final String reactionCode;
  final String reactionIconUrl;
  final String? avatarUrl;
  final DateTime? reactedAt;
}

class MessageReactionSummary {
  const MessageReactionSummary({
    required this.messageId,
    required this.totalReactions,
    this.myReactionCode,
    this.myReactionIconUrl,
    this.previewIconUrl,
  });

  final String messageId;
  final int totalReactions;
  final String? myReactionCode;
  final String? myReactionIconUrl;
  final String? previewIconUrl;
}
