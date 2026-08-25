import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/providers/shared_providers.dart';

/// Logic nghiệp vụ reaction của phòng (config reaction, reaction từng tin,
/// tổng hợp reaction toàn phòng).
///
/// Sống theo provider Riverpod để cache [ReactionConfig] tồn tại ngoài vòng
/// đời của `ThreadMessagesNotifier` (dùng chung cho mọi phòng).
class ThreadReactionsService {
  ThreadReactionsService(this._ref);

  final Ref _ref;
  List<ReactionConfig>? _configs;

  MessageRepository get _messageRepository =>
      _ref.read(messageRepositoryProvider);

  Future<List<ReactionConfig>> getReactionConfigs() async {
    final cached = _configs;
    if (cached != null) return cached;
    final configs = await _messageRepository.getReactionConfigs();
    _configs = configs;
    return configs;
  }

  Future<List<MessageReaction>> getMessageReactions({
    required String roomId,
    required String messageId,
  }) =>
      _messageRepository.getMessageReactions(
        roomId: roomId,
        messageId: messageId,
      );

  Future<bool> reactMessage({
    required String roomId,
    required String threadId,
    required String messageId,
    required String reactionCode,
  }) =>
      _messageRepository.reactMessage(
        roomId: roomId,
        threadId: threadId,
        messageId: messageId,
        reactionCode: reactionCode,
      );

  /// Lấy reaction của phòng và điền icon URL từ config (nếu BE thiếu).
  /// Trả `null` nếu provider đã bị dispose giữa chừng fetch.
  Future<Map<String, MessageReactionSummary>?> buildRoomReactionSummaries(
    String roomId,
  ) async {
    final results = await Future.wait([
      getReactionConfigs(),
      _messageRepository.getRoomReactions(roomId),
    ]);
    if (!_ref.mounted) return null;
    final configs = results[0] as List<ReactionConfig>;
    final summaries = results[1] as List<MessageReactionSummary>;
    final map = <String, MessageReactionSummary>{};
    for (final s in summaries) {
      var myIcon = s.myReactionIconUrl;
      var previewIcon = s.previewIconUrl;
      if ((myIcon == null || myIcon.isEmpty) && s.myReactionCode != null) {
        final matched =
            configs.where((c) => c.code == s.myReactionCode).firstOrNull;
        if (matched != null && matched.iconUrl.isNotEmpty) {
          myIcon = matched.iconUrl;
        }
      }
      if (previewIcon == null || previewIcon.isEmpty) {
        previewIcon = myIcon;
      }
      if ((previewIcon == null || previewIcon.isEmpty) && configs.isNotEmpty) {
        previewIcon = configs.first.iconUrl;
      }
      map[s.messageId] = MessageReactionSummary(
        messageId: s.messageId,
        totalReactions: s.totalReactions,
        myReactionCode: s.myReactionCode,
        myReactionIconUrl: myIcon,
        previewIconUrl: previewIcon,
      );
    }
    return map;
  }
}

final threadReactionsServiceProvider =
    Provider<ThreadReactionsService>(ThreadReactionsService.new);
