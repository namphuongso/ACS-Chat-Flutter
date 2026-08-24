import 'dart:async';

import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/providers/shared_providers.dart';

class ConversationListNotifier extends Notifier<List<Conversation>> {
  ListConversationsUseCase get _listConversationsUseCase =>
      ref.read(listConversationsUseCaseProvider);
  ConversationRepository get _conversationRepository =>
      ref.read(conversationRepositoryProvider);

  StreamSubscription<Message>? _listRealtimeSub;
  bool _listRealtimeStarted = false;
  String? _cursor;
  bool _isLoadingMore = false;

  @override
  List<Conversation> build() {
    ref.watch(listConversationsUseCaseProvider);
    ref.watch(conversationRepositoryProvider);
    final stopWatchingListUseCase =
        ref.watch(stopWatchingListMessagesUseCaseProvider);

    Future.microtask(() {
      unawaited(_initFromCache());
      unawaited(refresh());
    });

    ref.onDispose(() {
      unawaited(_listRealtimeSub?.cancel());
      unawaited(stopWatchingListUseCase());
    });

    return const [];
  }

  /// Bắt realtime cho toàn bộ danh sách: máy khác gửi tin → tin mới xuất
  /// hiện (lastMessage + đẩy lên đầu) ngay, không cần mở room/pull-to-refresh.
  void _startListRealtime() {
    if (_listRealtimeStarted) return;
    _listRealtimeStarted = true;
    _listRealtimeSub = ref
        .read(watchListMessagesUseCaseProvider)()
        .listen(_onNewMessage);
  }

  void _onNewMessage(Message message) {
    final metadata = message.metadata;
    final eventType = metadata?['eventType']?.toString();

    if (message.type == MessageType.roomDisbanded) {
      removeRoom(message.threadId);
      return;
    }
    if (eventType == 'MemberRemoved') {
      final payload = (metadata?['payload'] is Map) ? (metadata!['payload'] as Map).cast<String, dynamic>() : <String, dynamic>{};
      final removedUserId = (metadata?['removedUserId'] ?? payload['removedUserId'] ?? '').toString();
      final currentUserId = ref.read(globalCurrentUserIdProvider).isNotEmpty
          ? ref.read(globalCurrentUserIdProvider)
          : ref.read(currentUserIdProvider);

      final isSelfRemoved = metadata?['isSelf'] == true ||
          (removedUserId.isNotEmpty &&
              currentUserId.isNotEmpty &&
              AcsUserUtils.isSameAcsUser(removedUserId, currentUserId));
      if (isSelfRemoved) {
        removeRoom(message.threadId);
        return;
      }
    }
    if (eventType == 'MemberJoined' || message.type == MessageType.memberJoinedUpdate) {
      _scheduleRefreshForNewRoom();
      return;
    }
    if (message.type == MessageType.roomPinnedUpdate) {
      updateRoomPin(message.threadId, true);
      return;
    }
    if (message.type == MessageType.roomUnpinnedUpdate) {
      updateRoomPin(message.threadId, false);
      return;
    }
    if (message.type == MessageType.roomUpdatedUpdate) {
      final roomName = metadata?['roomName']?.toString();
      final avatarUrl = metadata?['avatarUrl']?.toString();
      updateRoomDetails(
        message.threadId,
        roomName: (roomName != null && roomName.isNotEmpty) ? roomName : null,
        avatarUrl: (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : null,
      );
      return;
    }
    if (message.type == MessageType.memberJoinedUpdate ||
        message.type == MessageType.memberLeftUpdate ||
        message.type == MessageType.memberRemovedUpdate) {
      return;
    }

    final currentUserId = ref.read(globalCurrentUserIdProvider).isNotEmpty
        ? ref.read(globalCurrentUserIdProvider)
        : ref.read(currentUserIdProvider);
    final isMe = message.senderId.isNotEmpty &&
        AcsUserUtils.isSameAcsUser(message.senderId, currentUserId);

    final idx = state.indexWhere((c) => c.id == message.threadId || c.threadId == message.threadId);
    if (idx != -1) {
      final conversation = state[idx];
      final updated = conversation.copyWith(
        lastMessage: ConversationSummary(
          content: _formatLastMessageContent(message),
          senderDisplayName: message.senderDisplayName,
          createdAt: message.createdAt,
          senderId: message.senderId,
        ),
        unreadCount: isMe ? 0 : conversation.unreadCount + 1,
      );
      state = _reorderWithUpdated(state, updated);
    } else {
      _scheduleRefreshForNewRoom();
    }
  }

  /// Preview tin nhắn cuối theo đúng format API trả về trong danh sách:
  /// "SenderName : Content". Tin realtime chỉ có content thô nên phải tự ghép.
  String _formatLastMessageContent(Message message) {
    final senderName = message.senderDisplayName.trim();
    if (senderName.isEmpty) return message.content;
    return '$senderName : ${message.content}';
  }

  bool _refreshScheduled = false;

  void _scheduleRefreshForNewRoom() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      _refreshScheduled = false;
      if (ref.mounted) refresh();
    });
  }

  /// Cache-first: hiện danh sách đã lưu ngay lập tức, sau đó refresh.
  Future<void> _initFromCache() async {
    final cached = await _conversationRepository.getCachedConversations();
    if (!ref.mounted) return;
    if (cached.isNotEmpty && state.isEmpty) {
      state = cached;
      ref.read(conversationListLoadingProvider.notifier).set(false);
      _startListRealtime();
    }
  }

  Future<void> refresh() async {
    if (state.isEmpty) {
      ref.read(conversationListLoadingProvider.notifier).set(true);
    }
    try {
      final result = await _listConversationsUseCase();
      if (!ref.mounted) return;
      state = _mergeConversations(state, result.items);
      _cursor = result.cursor;
      _startListRealtime();
      ref.read(conversationListLoadingProvider.notifier).set(false);
    } catch (e, st) {
      ChatLogger.error('Error refreshing conversation list',
          error: e, stackTrace: st);
      if (ref.mounted) {
        ref.read(conversationListLoadingProvider.notifier).set(false);
      }
    }
  }

  List<Conversation> _mergeConversations(
      List<Conversation> current, List<Conversation> fresh) {
    if (current.isEmpty) return fresh;
    final mapCurrent = {for (final c in current) c.id: c};
    return fresh.map((freshRoom) {
      final oldRoom = mapCurrent[freshRoom.id];
      if (oldRoom == null) return freshRoom;

      final oldMemberMap = {for (final p in oldRoom.participants) p.id: p};
      final mergedParticipants = freshRoom.participants.map((freshMember) {
        final oldMember = oldMemberMap[freshMember.id];
        if (oldMember != null &&
            oldMember.avatarUrl != null &&
            oldMember.avatarUrl!.isNotEmpty &&
            (freshMember.avatarUrl == null || freshMember.avatarUrl!.isEmpty)) {
          return ChatMember(
            id: freshMember.id,
            displayName: freshMember.displayName,
            avatarUrl: oldMember.avatarUrl,
            acsUserId: freshMember.acsUserId,
            email: freshMember.email,
            isAdmin: freshMember is ChatMember ? freshMember.isAdmin : false,
          );
        }
        return freshMember;
      }).toList();

      return freshRoom.copyWith(
        participants: mergedParticipants,
        avatarUrl: (freshRoom.avatarUrl != null && freshRoom.avatarUrl!.isNotEmpty)
            ? freshRoom.avatarUrl
            : oldRoom.avatarUrl,
      );
    }).toList();
  }

  Future<void> loadMore() async {
    if (_cursor == null || _isLoadingMore) return;
    _isLoadingMore = true;
    try {
      final result = await _listConversationsUseCase(cursor: _cursor);
      if (!ref.mounted) return;

      final existingIds = state.map((c) => c.id).toSet();
      final newItems =
          result.items.where((c) => !existingIds.contains(c.id)).toList();

      if (newItems.isEmpty) {
        _cursor = null;
      } else {
        state = [...state, ...newItems];
        _cursor = result.cursor;
      }
    } finally {
      _isLoadingMore = false;
    }
  }

  bool get isLoadingMore => _isLoadingMore;

  bool get hasMore => _cursor != null;

  void updateRoomPin(String roomId, bool pin) {
    final idx = state.indexWhere((c) => c.id == roomId || c.threadId == roomId);
    if (idx == -1) return;
    final updated = state[idx].copyWith(pin: pin);
    state = _reorderWithUpdated(state, updated);
  }

  void markAsRead(String roomId) {
    state = state.map((c) {
      if (c.id == roomId || c.threadId == roomId) {
        return c.copyWith(unreadCount: 0);
      }
      return c;
    }).toList();
  }

  void removeRoom(String roomId) {
    state = state.where((c) => c.id != roomId).toList();
  }

  void updateRoomParticipants(String roomId, List<ChatUser> participants) {
    state = state
        .map((c) => c.id == roomId ? c.copyWith(participants: participants) : c)
        .toList();
  }

  void updateRoomDetails(
    String roomId, {
    String? roomName,
    String? avatarUrl,
    List<ChatUser>? participants,
  }) {
    state = state
        .map((room) => room.id == roomId
            ? room.copyWith(
                roomName: roomName,
                avatarUrl: avatarUrl,
                participants: participants,
              )
            : room)
        .toList();
  }

  /// Thêm hoặc cập nhật 1 room vào danh sách (dùng ngay sau khi tạo phòng
  /// trực tiếp từ danh bạ) — room mới hiện ngay, không cần pull-to-refresh.
  void addOrUpdateRoom(Conversation conversation) {
    state = _reorderWithUpdated(state, conversation);
  }

  /// Cập nhật tin nhắn cuối + đẩy room lên đầu khi có tin mới (real-time
  /// hoặc vừa gửi tin từ trong thread). Ghim luôn ở trên cùng.
  void updateLastMessage(String threadId, Message message) {
    if (message.type == MessageType.reactionUpdate) return;
    // WebSocket backend chỉ có roomId, còn history ACS từng dùng threadId.
    // Chấp nhận cả hai routing key để last message cập nhật tức thời.
    final idx = state.indexWhere(
      (c) => c.threadId == threadId || c.id == threadId,
    );
    if (idx == -1) return;
    final conversation = state[idx];
    final updated = conversation.copyWith(
      lastMessage: ConversationSummary(
        content: _formatLastMessageContent(message),
        senderDisplayName: message.senderDisplayName,
        createdAt: message.createdAt,
        senderId: message.senderId,
      ),
    );
    state = _reorderWithUpdated(state, updated);
  }

  /// Sắp xếp lại danh sách phòng:
  /// - Nếu room được ghim (`pin == true`): nhảy lên đầu nhóm ghim.
  /// - Nếu room không ghim (`pin == false`): nhảy lên đầu nhóm không ghim.
  List<Conversation> _reorderWithUpdated(
      List<Conversation> currentList, Conversation updated) {
    final rest = currentList.where((c) => c.id != updated.id).toList();
    final pinned = rest.where((c) => c.pin).toList();
    final unpinned = rest.where((c) => !c.pin).toList();

    if (updated.pin) {
      return [updated, ...pinned, ...unpinned];
    } else {
      return [...pinned, updated, ...unpinned];
    }
  }

}

/// Trạng thái đang load lần đầu của danh sách room — dùng cho skeleton
/// loading (tránh nhầm với "chưa có cuộc trò chuyện nào" khi danh sách rỗng).
class ConversationListLoading extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

final conversationListLoadingProvider =
    NotifierProvider<ConversationListLoading, bool>(
        ConversationListLoading.new);
