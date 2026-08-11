import 'dart:async';
import 'dart:developer' as developer;

import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/thread_providers.dart';
import '../../../conversation_list/presentation/providers/conversation_providers.dart';
import '../../../shared/presentation/providers/connectivity_providers.dart';
import '../../../shared/data/local/hive_identity_store.dart';
import '../../../shared/presentation/providers/local_cache_providers.dart';
import '../../../shared/presentation/providers/shared_providers.dart';

class ThreadMessagesNotifier extends Notifier<List<Message>> {
  late String roomId;
  late String threadId;
  late String currentUserId;

  late final ListMessagesUseCase _listMessagesUseCase;
  late final WatchNewMessagesUseCase _watchNewMessagesUseCase;
  late final SendMessageUseCase _sendMessageUseCase;
  late final UpdateMessageUseCase _updateMessageUseCase;
  late final DeleteMessageUseCase _deleteMessageUseCase;
  late final PinMessageUseCase _pinMessageUseCase;
  late final StopWatchingMessagesUseCase _stopWatchingUseCase;
  late final GetPinnedMessagesUseCase _getPinnedMessagesUseCase;
  late final MessageRepository _messageRepository;
  late final HiveIdentityStore _identityStore;
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
    currentUserId = ref.watch(currentUserIdProvider);

    _listMessagesUseCase = ref.watch(listMessagesUseCaseProvider);
    _watchNewMessagesUseCase = ref.watch(watchNewMessagesUseCaseProvider);
    _sendMessageUseCase = ref.watch(sendMessageUseCaseProvider);
    _updateMessageUseCase = ref.watch(updateMessageUseCaseProvider);
    _deleteMessageUseCase = ref.watch(deleteMessageUseCaseProvider);
    _pinMessageUseCase = ref.watch(pinMessageUseCaseProvider);
    _stopWatchingUseCase = ref.watch(stopWatchingMessagesUseCaseProvider);
    _getPinnedMessagesUseCase = ref.watch(getPinnedMessagesUseCaseProvider);
    _messageRepository = ref.watch(messageRepositoryProvider);
    _identityStore = ref.watch(identityStoreProvider);

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

    // 3. Đã có identity → lưu lại để lần sau khôi phục nhanh (mọi room dùng
    //    chung acsUserId này), tránh phải chờ join-room mới biết mình là ai.
    if (myAcsUserId != null && myAcsUserId!.isNotEmpty) {
      unawaited(_identityStore.setMyAcsUserId(currentUserId, myAcsUserId));
    }

    _realtimeSub = _watchNewMessagesUseCase(roomId, threadId).listen((message) {
      // Tin bị xoá (soft-delete ACS): đánh dấu deletedOn thay vì loại khỏi
      // danh sách — UI hiển thị placeholder "(tin nhắn đã bị xoá)".
      if (message.isDeleted) {
        final i = state.indexWhere((m) => m.id == message.id);
        if (i != -1) {
          state = [...state];
          state[i] = state[i].copyWith(deletedOn: message.deletedOn);
        }
        return;
      }
      if (state.any((m) => m.id == message.id)) return;
      // Echo của chính tin mình đang gửi dở (optimistic chưa có id thật từ
      // server): thay optimistic bằng tin thật thay vì thêm bản trùng →
      // tránh "lật/giật" do xuất hiện 2 tin giống nhau rồi cuộn lại.
      final pending = state.where((m) =>
          m.status == MessageDeliveryStatus.sending &&
          m.content == message.content).firstOrNull;
      if (pending != null) {
        state = state.map((m) => m.id == pending.id ? message : m).toList();
        return;
      }
      // Chèn đúng vị trí theo thời gian để giữ list tăng dần — không sort lại
      // toàn bộ (tránh nhảy thứ tự khi timestamp trùng nhau).
      final list = [...state];
      final insertAt =
          list.indexWhere((m) => m.createdAt.isAfter(message.createdAt));
      if (insertAt == -1) {
        list.add(message);
      } else {
        list.insert(insertAt, message);
      }
      state = list;
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
  /// Xác định danh tính (`myAcsUserId`) để `isMe` (bên trái/phải) đúng.
  /// Không đặt timeout nhỏ hơn ngưỡng HTTP client (15s) — nếu join-room về
  /// chậm trong khoảng 8-15s, timeout 8s cũ bắn trước và bỏ qua token
  /// khiến myAcsUserId mãi null → mọi tin hiện sai phía. Timeout 20s để
  /// nhường cho HTTP client 15s là ngưỡng chặn thật; khi fail vẫn hiện cache.
  Future<void> _loadHistory() async {
    // 0. Khôi phục danh tính đã lưu trên disk (acsUserId dùng chung mọi room).
    //    Đọc local nhanh, không cần mạng → tin render đúng phía ngay lần vào
    //    đầu, không kẹt spinner chờ join-room.
    if (myAcsUserId == null) {
      try {
        final saved =
            await _identityStore.getMyAcsUserId(currentUserId);
        if (ref.mounted && saved != null && saved.isNotEmpty) {
          myAcsUserId = saved;
        }
      } catch (_) {}
    }

    // 1. Nếu đã biết danh tính (myAcsUserId từ participant/token cache) thì
    //    hiện cache ngay — paint nhanh và đúng phía. Lần vào lại session sẽ
    //    vào nhánh này.
    if (myAcsUserId != null) {
      await _showCachedMessagesIfAny();
    }

    // 2. Đảm bảo danh tính trước khi hiển thị tin: nếu chưa có myAcsUserId
    //    mà render tin thì `isMe` = false cho TẤT CẢ (mọi tin nằm bên trái,
    //    sai người gửi) — đúng bug "vô vào bị sai, back ra vào lại mới đúng".
    //    Timeout 20s nhường cho HTTP client (15s) làm ngưỡng chặn thật; khi
    //    fail vẫn hiện cache (degraded).
    try {
      final token = await ref
          .read(authTokenRepositoryProvider)
          .getAccessToken(roomId)
          .timeout(const Duration(seconds: 20));
      if (ref.mounted) {
        myAcsUserId = token.acsUserId;
        developer.log('myAcsUserId set from join-room: $myAcsUserId '
            'participants=${token.participants.length} '
            'room=$roomId',
            name: 'ChatModule');
        unawaited(_identityStore.setMyAcsUserId(currentUserId, myAcsUserId));
        if (token.participants.isNotEmpty) {
          ref
              .read(conversationListProvider.notifier)
              .updateRoomParticipants(roomId, token.participants);
        }
        if (state.isEmpty) {
          await _showCachedMessagesIfAny();
        } else {
          state = [...state];
        }
      }
    } catch (e, st) {
      // join-room fail — log ra để debug. Trước đây `catch (_) {}` nuốt lỗi
      // âm thầm nên không biết request treo/hết hạn/lỗi HTTP.
      developer.log('join-room/getAccessToken failed',
          name: 'ChatModule', error: e, stackTrace: st);
      await _showCachedMessagesIfAny();
    }

    try {
      final result =
          await _listMessagesUseCase(roomId: roomId, threadId: threadId);
      if (!ref.mounted) return;

      final remoteItems = result.items.toList();
      // Giữ tin local chưa có trên remote (tin đang gửi dở / vừa gửi mà list
      // API chưa kịp trả) — trước đây replace toàn bộ bằng remote làm tin vừa
      // gửi biến mất rồi hiện lại qua realtime → cảm giác "lật ngược tin".
      final remoteIds = remoteItems.map((m) => m.id).toSet();
      final localExtras = state
          .where((m) => !remoteIds.contains(m.id))
          .toList();
      final mergedItems = remoteItems.map((remoteMsg) {
        final localMsg = state.where((m) => m.id == remoteMsg.id).firstOrNull;
        if (localMsg != null && localMsg.pin) {
          return remoteMsg.copyWith(pin: true);
        }
        return remoteMsg;
      }).toList();

      state = _chronological([...mergedItems, ...localExtras]);
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

  /// Hiện cache nếu có và state đang trống — dùng chung cho các nhánh
  /// "đã có identity" và "join chậm/fail". Chỉ render khi biết myAcsUserId
  /// để không vẽ tin sai phía.
  Future<void> _showCachedMessagesIfAny() async {
    try {
      final cached = await _messageRepository.getCachedMessages(threadId);
      final visible = cached.toList();
      if (ref.mounted && visible.isNotEmpty && state.isEmpty) {
        state = _chronological(visible);
        _historyLoaded = true;
        state = [...state];
      }
    } catch (_) {}
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
      final visible = result.items.toList();
      state = [..._chronological(visible), ...state];
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

  /// Sắp xếp theo thời gian tăng dần (cũ → mới) — thứ tự display chuẩn của
  /// `state` (ListView reverse: index nhỏ = tin cũ). KHÔNG phụ thuộc thứ tự
  /// lưu cache: trước đây cache đọc ra rồi `.reversed` — nếu thứ tự lưu bị
  /// lệch (vd realtime append tin mới vào cuối khiến cache không còn
  /// mới-nhất-trước) thì lần vào đầu render bị đảo ngược rồi mới tự sửa.
  List<Message> _chronological(Iterable<Message> msgs) {
    final list = msgs.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

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
      // Thay optimistic bằng tin thật, đồng thời loại bản trùng cùng id
      // (nếu echo realtime đã được chèn vào trước đó) để không hiện 2 tin
      // giống nhau. Tin vừa gửi là mới nhất → append cuối giữ nguyên thứ tự.
      final deduped = state
          .where((m) => m.id != optimisticId && m.id != sent.id)
          .toList();
      state = [...deduped, sent];
      // Cập nhật tin cuối + đẩy room lên đầu danh sách chat gần đây.
      ref.read(conversationListProvider.notifier).updateLastMessage(threadId, sent);
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

  /// Sửa nội dung tin nhắn (chỉ tin của mình). Optimistic — cập nhật UI
  /// ngay, nếu BE thất bại thì rollback về nội dung cũ.
  Future<bool> updateMessage(String messageId, String newContent) async {
    final trimmed = newContent.trim();
    if (trimmed.isEmpty) return false;

    final oldContent =
        state.where((m) => m.id == messageId).firstOrNull?.content;
    if (oldContent == trimmed) return true;

    state = state
        .map((m) => m.id == messageId ? m.copyWith(content: trimmed) : m)
        .toList();

    try {
      final ok = await _updateMessageUseCase(
        roomId: roomId,
        threadId: threadId,
        messageId: messageId,
        content: trimmed,
      );
      if (!ok && ref.mounted) {
        _revertMessageContent(messageId, oldContent);
      }
      return ok;
    } catch (e, st) {
      developer.log('update-message failed',
          name: 'ChatModule', error: e, stackTrace: st);
      if (ref.mounted) {
        _revertMessageContent(messageId, oldContent);
      }
      return false;
    }
  }

  void _revertMessageContent(String messageId, String? oldContent) {
    if (oldContent == null) return;
    state = state
        .map((m) => m.id == messageId ? m.copyWith(content: oldContent) : m)
        .toList();
  }

  /// Xoá tin nhắn. Nếu tin đang được ghim thì bỏ ghim trước rồi mới xoá.
  /// Xoá thành công → ẩn tin ngay (cập nhật UI, không cần chờ refresh) và
  /// làm mới banner tin ghim.
  Future<bool> deleteMessage(String messageId) async {
    final target = state.where((m) => m.id == messageId).firstOrNull;
    if (target == null) return false;

    // BE không cho xoá tin đang ghim → bỏ ghim trước.
    if (target.pin) {
      try {
        final unpinned = await _pinMessageUseCase(
          threadId: threadId,
          messageId: messageId,
          pin: false,
        );
        if (!unpinned) return false;
      } catch (_) {
        return false;
      }
    }

    try {
      final ok = await _deleteMessageUseCase(
        roomId: roomId,
        threadId: threadId,
        messageId: messageId,
      );
      if (!ref.mounted) return false;
      if (ok) {
        // Không ẩn hẳn — đánh dấu deletedOn để UI hiện placeholder
        // "(tin nhắn đã bị xoá)" ngay, không cần chờ refresh lại lịch sử.
        state = state
            .map((m) => m.id == messageId
                ? m.copyWith(deletedOn: DateTime.now())
                : m)
            .toList();
        // Banner ghim có thể chứa tin vừa xoá → cập nhật lại.
        await _loadPinnedMessages();
      }
      return ok;
    } catch (e, st) {
      developer.log('delete-message failed',
          name: 'ChatModule', error: e, stackTrace: st);
      return false;
    }
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
