import 'dart:async';

import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../thread/presentation/providers/thread_providers.dart';
import '../../../shared/presentation/providers/shared_providers.dart';

class ConversationListNotifier extends Notifier<List<Conversation>> {
  late final ListConversationsUseCase _listConversationsUseCase;
  late final ConversationRepository _conversationRepository;
  StreamSubscription<Message>? _listRealtimeSub;
  bool _listRealtimeStarted = false;
  String? _cursor;
  bool _isLoadingMore = false;

  @override
  List<Conversation> build() {
    _listConversationsUseCase = ref.watch(listConversationsUseCaseProvider);
    _conversationRepository = ref.watch(conversationRepositoryProvider);
    unawaited(_initFromCache());
    unawaited(refresh());

    ref.onDispose(() {
      unawaited(_listRealtimeSub?.cancel());
      unawaited(ref.read(stopWatchingListMessagesUseCaseProvider)());
    });

    return const [];
  }

  /// Bắt realtime cho toàn bộ danh sách: máy khác gửi tin → tin mới xuất
  /// hiện (lastMessage + đẩy lên đầu) ngay, không cần mở room/pull-to-refresh.
  void _startListRealtime() {
    if (_listRealtimeStarted) return;
    final firstRoom = state.firstOrNull;
    if (firstRoom == null) return;
    _listRealtimeStarted = true;
    _listRealtimeSub = ref
        .read(watchListMessagesUseCaseProvider)(firstRoom.id)
        .listen(_onNewMessage);
  }

  void _onNewMessage(Message message) {
    final idx = state.indexWhere((c) => c.threadId == message.threadId);
    if (idx == -1) return;
    final conversation = state[idx];
    final updated = conversation.copyWith(
      lastMessage: ConversationSummary(
        content: message.content,
        senderDisplayName: message.senderDisplayName,
        createdAt: message.createdAt,
      ),
    );
    final rest = state.where((c) => c.id != updated.id).toList();
    final pinned = rest.where((c) => c.pin).toList();
    final unpinned = rest.where((c) => !c.pin).toList();
    // Ghim luôn ở trên; hội thoại vừa có tin mới đẩy lên đầu phần không ghim.
    state = [...pinned, updated, ...unpinned];
  }

  /// Cache-first: hiện danh sách đã lưu ngay lập tức, sau đó refresh.
  Future<void> _initFromCache() async {
    final cached = await _conversationRepository.getCachedConversations();
    if (!ref.mounted) return;
    if (cached.isNotEmpty && state.isEmpty) {
      state = cached;
      _startListRealtime();
    }
  }

  Future<void> refresh() async {
    try {
      final result = await _listConversationsUseCase();
      if (!ref.mounted) return;
      state = result.items;
      _cursor = result.cursor;
      _startListRealtime();
    } catch (_) {
      // Offline / lỗi mạng — repository đã trả cache, hoặc giữ nguyên state.
    }
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
    state =
        state.map((c) => c.id == roomId ? c.copyWith(pin: pin) : c).toList();
  }

  void updateRoomParticipants(String roomId, List<ChatUser> participants) {
    state = state
        .map((c) => c.id == roomId ? c.copyWith(participants: participants) : c)
        .toList();
  }
}
