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
    Future.microtask(() {
      unawaited(_initFromCache());
      unawaited(refresh());
    });

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
    final exists = state.any((c) => c.threadId == message.threadId);
    if (exists) {
      updateLastMessage(message.threadId, message);
      return;
    }
    // Tin từ 1 room CHƯA có trong danh sách — vd người khác trên web tạo
    // room mới với mình rồi nhắn luôn. Trước đây bỏ qua event này → room
    // mới chỉ hiện khi tắt app mở lại (gọi lại get-room-chats). Giờ tự
    // fetch lại danh sách để room mới hiện ngay. Debounce để không spam
    // get-room-chats khi có nhiều tin từ cùng 1 room mới.
    _scheduleRefreshForNewRoom();
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
      state = result.items;
      _cursor = result.cursor;
      _startListRealtime();
      ref.read(conversationListLoadingProvider.notifier).set(false);
    } catch (_) {
      // Offline / lỗi mạng — repository đã trả cache, hoặc giữ nguyên state.
      if (ref.mounted) {
        ref.read(conversationListLoadingProvider.notifier).set(false);
      }
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

  /// Thêm hoặc cập nhật 1 room vào danh sách (dùng ngay sau khi tạo phòng
  /// trực tiếp từ danh bạ) — room mới hiện ngay, không cần pull-to-refresh.
  void addOrUpdateRoom(Conversation conversation) {
    final rest = state.where((c) => c.id != conversation.id).toList();
    state = [..._pinnedFirst(rest), conversation, ..._unpinnedFirst(rest)];
  }

  /// Cập nhật tin nhắn cuối + đẩy room lên đầu khi có tin mới (real-time
  /// hoặc vừa gửi tin từ trong thread). Ghim luôn ở trên cùng.
  void updateLastMessage(String threadId, Message message) {
    final idx = state.indexWhere((c) => c.threadId == threadId);
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
    state = [..._pinnedFirst(rest), updated, ..._unpinnedFirst(rest)];
  }

  List<Conversation> _pinnedFirst(List<Conversation> list) =>
      list.where((c) => c.pin).toList();

  List<Conversation> _unpinnedFirst(List<Conversation> list) =>
      list.where((c) => !c.pin).toList();
}

/// Trạng thái đang load lần đầu của danh sách room — dùng cho skeleton
/// loading (tránh nhầm với "chưa có cuộc trò chuyện nào" khi danh sách rỗng).
class ConversationListLoading extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

final conversationListLoadingProvider =
    NotifierProvider<ConversationListLoading, bool>(ConversationListLoading.new);
