import 'dart:async';
import 'dart:developer' as developer;

import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/thread_providers.dart';
import '../../../conversation_list/presentation/providers/conversation_providers.dart';
import '../../../shared/presentation/providers/connectivity_providers.dart';
import '../../../shared/presentation/providers/shared_providers.dart';

class ThreadMessagesNotifier extends Notifier<List<Message>> {
  late String roomId;
  late String threadId;

  late final ListMessagesUseCase _listMessagesUseCase;
  late final WatchNewMessagesUseCase _watchNewMessagesUseCase;
  late final SendMessageUseCase _sendMessageUseCase;
  late final StopWatchingMessagesUseCase _stopWatchingUseCase;
  late final GetPinnedMessagesUseCase _getPinnedMessagesUseCase;
  late final MessageRepository _messageRepository;
  StreamSubscription<Message>? _realtimeSub;
  String? myAcsUserId;

  String? _cursor;
  bool _hasMore = false;
  bool _isLoadingOlder = false;
  bool _historyLoaded = false;

  /// Tin đang ghim của room lấy từ BE — mọi user trong room đều thấy
  /// (ACS không mang thông tin ghim). Rỗng nếu chưa có ghim / BE lỗi.
  List<PinnedMessage> _pinned = const [];

  List<PinnedMessage> get pinnedMessages => _pinned;

  @override
  List<Message> build() {
    roomId = ref.watch(roomIdProvider);
    threadId = ref.watch(threadIdProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    _listMessagesUseCase = ref.watch(listMessagesUseCaseProvider);
    _watchNewMessagesUseCase = ref.watch(watchNewMessagesUseCaseProvider);
    _sendMessageUseCase = ref.watch(sendMessageUseCaseProvider);
    _stopWatchingUseCase = ref.watch(stopWatchingMessagesUseCaseProvider);
    _getPinnedMessagesUseCase = ref.watch(getPinnedMessagesUseCaseProvider);
    _messageRepository = ref.watch(messageRepositoryProvider);

    // 1. Cố gắng tìm acsUserId của bản thân trong danh sách participant của phòng chat hiện tại (đồng bộ)
    try {
      final conversations = ref.read(conversationListProvider);
      final conversation =
          conversations.where((c) => c.id == roomId).firstOrNull;
      if (conversation != null) {
        final me = conversation.participants
            .where((p) => p.id == currentUserId)
            .firstOrNull;
        if (me != null && me.acsUserId != null) {
          myAcsUserId = me.acsUserId;
        }
      }
    } catch (_) {}

    // 2. Fallback đọc từ token cache
    if (myAcsUserId == null) {
      final cachedToken =
          ref.read(authTokenRepositoryProvider).getCachedToken(roomId);
      if (cachedToken != null) {
        myAcsUserId = cachedToken.acsUserId;
      }
    }

    _realtimeSub = _watchNewMessagesUseCase(roomId, threadId).listen((message) {
      if (state.any((m) => m.id == message.id)) return;
      state = [...state, message];
    });

    ref.onDispose(() {
      unawaited(_realtimeSub?.cancel());
      unawaited(_stopWatchingUseCase(threadId));
    });

    unawaited(_loadHistory());
    return const [];
  }

  /// Cache-first: hiện tin đã lưu ngay lập tức, sau đó refresh từ remote
  /// để cập nhật tin mới nhất. Khi offline, remote fail → giữ nguyên cache.
  ///
  /// Thứ tự quan trọng: xác định danh tính (`myAcsUserId`) TRƯỚC khi hiển thị
  /// bất kỳ tin nào — `isMe` (hiển thị bên trái/phải) phụ thuộc vào nó. Nếu
  /// join-room chậm/thất bại, timeout 8s để không kẹt loading mà vẫn hiển thị
  /// cache (degraded: không phân biệt được bên mình/người khác).
  Future<void> _loadHistory() async {
    try {
      final cached = await _messageRepository.getCachedMessages(threadId);
      if (ref.mounted && cached.isNotEmpty) {
        state = cached.reversed.toList();
        _historyLoaded = true;
        state = [...state];
      }
    } catch (_) {}

    try {
      final token = await ref
          .read(authTokenRepositoryProvider)
          .getAccessToken(roomId)
          .timeout(const Duration(seconds: 8));
      if (ref.mounted) {
        myAcsUserId = token.acsUserId;
        if (token.participants.isNotEmpty) {
          ref
              .read(conversationListProvider.notifier)
              .updateRoomParticipants(roomId, token.participants);
        }
        state = [...state];
      }
    } catch (e, st) {
      // join-room fail — log ra để debug. Trước đây `catch (_) {}` nuốt lỗi
      // âm thầm nên không biết request treo/hết hạn/lỗi HTTP.
      developer.log('join-room/getAccessToken failed',
          name: 'ChatModule', error: e, stackTrace: st);
    }

    try {
      final result =
          await _listMessagesUseCase(roomId: roomId, threadId: threadId);
      if (!ref.mounted) return;

      final remoteItems = result.items;
      final mergedItems = remoteItems.map((remoteMsg) {
        final localMsg = state.where((m) => m.id == remoteMsg.id).firstOrNull;
        if (localMsg != null && localMsg.pin) {
          return remoteMsg.copyWith(pin: true);
        }
        return remoteMsg;
      }).toList();

      state = mergedItems.reversed.toList();
      _cursor = result.cursor;
      _hasMore = result.hasMore;
    } catch (e, st) {
      developer.log('Error loading messages from remote',
          name: 'ChatModule', error: e, stackTrace: st);
      if (!ref.mounted) return;
    } finally {
      _historyLoaded = true;
      unawaited(_loadPinnedMessages());
      if (ref.mounted) {
        state = [...state];
      }
    }
  }

  /// Lấy danh sách tin ghim từ BE rồi:
  /// 1. Lưu vào [_pinned] — banner ở đầu màn hình luôn hiện được kể cả khi
  ///    tin ghim chưa được load (nằm ở trang cũ hơn).
  /// 2. Gắn cờ `pin` cho các tin đang hiển thị có id khớp.
  Future<void> _loadPinnedMessages() async {
    try {
      final pinned = await _getPinnedMessagesUseCase(roomId);
      if (!ref.mounted) return;
      _pinned = pinned;
      final pinnedIds = <String>{for (final p in pinned) p.messageId};
      if (pinnedIds.isNotEmpty) {
        state = [
          for (final m in state)
            if (pinnedIds.contains(m.id)) m.copyWith(pin: true) else m,
        ];
      }
    } catch (_) {
      // BE lỗi / offline — giữ nguyên, banner chỉ là tin đã ghim local.
    }
  }

  /// Gọi lại sau khi ghim/bỏ ghim 1 tin để banner + cờ pin cập nhật.
  Future<void> refreshPinned() => _loadPinnedMessages();

  /// Gọi lại khi vừa có mạng trở lại — refresh lịch sử mới từ remote.
  Future<void> refreshHistory() => _loadHistory();

  /// Load tin cũ hơn (phân trang) — cursor từ trang trước. Chỉ chạy khi
  /// có cursor và đang online.
  Future<void> loadOlder() async {
    if (_cursor == null || _isLoadingOlder) return;
    if (!(ref.read(isOnlineProvider).value ?? true)) return;

    _isLoadingOlder = true;
    try {
      final result = await _listMessagesUseCase(
          roomId: roomId, threadId: threadId, cursor: _cursor);
      if (!ref.mounted) return;
      state = [...result.items.reversed.toList(), ...state];
      _cursor = result.cursor;
      _hasMore = result.hasMore;
    } catch (e, st) {
      developer.log('Error loading older messages',
          name: 'ChatModule', error: e, stackTrace: st);
    } finally {
      _isLoadingOlder = false;
    }
  }

  bool get isLoadingOlder => _isLoadingOlder;

  bool get hasMore => _hasMore;

  bool get historyLoaded => _historyLoaded;

  Future<void> sendMessage(String content) async {
    final optimisticId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Message(
      id: optimisticId,
      threadId: threadId,
      senderId: myAcsUserId ?? '',
      senderDisplayName: '',
      content: content,
      type: MessageType.text,
      createdAt: DateTime.now(),
      status: MessageDeliveryStatus.sending,
    );
    state = [...state, optimistic];

    try {
      final sent = await _sendMessageUseCase(
        roomId: roomId,
        threadId: threadId,
        content: content,
      );
      if (!ref.mounted) return;
      state = state.map((m) => m.id == optimisticId ? sent : m).toList();
    } catch (_) {
      if (!ref.mounted) return;
      state = state
          .map((m) => m.id == optimisticId
              ? m.copyWith(status: MessageDeliveryStatus.failed)
              : m)
          .toList();
    }
  }

  void updateMessagePin(String messageId, bool pin) {
    state =
        state.map((m) => m.id == messageId ? m.copyWith(pin: pin) : m).toList();
  }

  /// Tự động load thêm tin nhắn cũ hơn cho đến khi chứa tin nhắn có [messageId].
  /// Trả về true nếu tìm thấy, false nếu không tìm thấy (hoặc hết lịch sử).
  Future<bool> loadUntilMessage({required String messageId}) async {
    if (state.any((m) => m.id == messageId)) {
      return true;
    }

    while (true) {
      if (_cursor == null) {
        break;
      }
      if (_isLoadingOlder) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (state.any((m) => m.id == messageId)) return true;
        continue;
      }

      await loadOlder();

      if (state.any((m) => m.id == messageId)) {
        return true;
      }
    }
    return state.any((m) => m.id == messageId);
  }
}
