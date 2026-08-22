import 'dart:async';

import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/thread_providers.dart';
import '../services/message_media_upload_service.dart';
import '../services/thread_reactions_service.dart';
import '../../../conversation_list/presentation/providers/conversation_providers.dart';
import '../../../shared/presentation/providers/connectivity_providers.dart';
import '../../../shared/data/local/hive_identity_store.dart';
import '../../../shared/presentation/providers/local_cache_providers.dart';
import '../../../../core/utils/link_preview_fetcher.dart';
import '../../../../core/utils/avatar_utils.dart';

class ThreadMessagesNotifier extends Notifier<ThreadState> {
  late String roomId;
  late String threadId;
  late String currentUserId;

  ListMessagesUseCase get _listMessagesUseCase =>
      ref.read(listMessagesUseCaseProvider);
  WatchNewMessagesUseCase get _watchNewMessagesUseCase =>
      ref.read(watchNewMessagesUseCaseProvider);
  SendMessageUseCase get _sendMessageUseCase =>
      ref.read(sendMessageUseCaseProvider);
  UpdateMessageUseCase get _updateMessageUseCase =>
      ref.read(updateMessageUseCaseProvider);
  DeleteMessageUseCase get _deleteMessageUseCase =>
      ref.read(deleteMessageUseCaseProvider);
  PinMessageUseCase get _pinMessageUseCase =>
      ref.read(pinMessageUseCaseProvider);
  GetPinnedMessagesUseCase get _getPinnedMessagesUseCase =>
      ref.read(getPinnedMessagesUseCaseProvider);
  MessageRepository get _messageRepository =>
      ref.read(messageRepositoryProvider);
  HiveIdentityStore get _identityStore => ref.read(identityStoreProvider);
  StreamSubscription<Message>? _realtimeSub;

  /// Danh tính ACS của mình (`null` nếu chưa resolve được).
  String? get myAcsUserId =>
      state.myAcsUserId.isEmpty ? null : state.myAcsUserId;

  List<Message> get _messages => state.messages;
  final Map<String, String> _userAvatarCache = {};

  void cacheUserAvatar(String userId, String avatarUrl) {
    if (userId.isEmpty || avatarUrl.isEmpty || !isNetworkAvatar(avatarUrl))
      return;
    final norm = AcsUserUtils.normalizeAcsId(userId);
    if (norm.isNotEmpty) {
      _userAvatarCache[norm] = avatarUrl;
    }
  }

  String? getAvatarUrlForUser(String userId) {
    if (userId.isEmpty) return null;
    final norm = AcsUserUtils.normalizeAcsId(userId);
    final cached = _userAvatarCache[norm];
    if (cached != null && isNetworkAvatar(cached)) {
      return cached;
    }
    return null;
  }

  void _cacheParticipantAvatars(List<ChatUser> participants) {
    for (final p in participants) {
      final av = p.avatarUrl;
      if (av != null && isNetworkAvatar(av)) {
        cacheUserAvatar(p.id, av);
        final acs = p.acsUserId;
        if (acs != null && acs.isNotEmpty) {
          cacheUserAvatar(acs, av);
        }
      }
    }
  }

  /// Tin đang ghim của room lấy từ BE — mọi user trong room đều thấy
  /// (ACS không mang thông tin ghim). Rỗng nếu chưa có ghim / BE lỗi.
  ThreadReactionsService get _reactionsService =>
      ref.read(threadReactionsServiceProvider);

  List<PinnedMessage> get pinnedMessages => state.pinnedMessages;

  MessageReactionSummary? reactionSummaryFor(String messageId) =>
      state.reactionsMap[messageId];

  Future<List<ReactionConfig>> getReactionConfigs() =>
      _reactionsService.getReactionConfigs();

  Future<List<MessageReaction>> getMessageReactions(String messageId) =>
      _reactionsService.getMessageReactions(
        roomId: roomId,
        messageId: messageId,
      );

  Future<bool> reactMessage(String messageId, String reactionCode) async {
    final ok = await _reactionsService.reactMessage(
      roomId: roomId,
      threadId: threadId,
      messageId: messageId,
      reactionCode: reactionCode,
    );
    if (ok) await refreshReactions();
    return ok;
  }

  Future<void> refreshReactions() async {
    try {
      final map = await _reactionsService.buildRoomReactionSummaries(roomId);
      if (map == null || !ref.mounted) return;
      state = state.copyWith(reactionsMap: map);
    } catch (_) {}
  }

  @override
  ThreadState build() {
    roomId = ref.watch(roomIdProvider);
    threadId = ref.watch(threadIdProvider);
    currentUserId = ref.watch(currentUserIdProvider);

    final stopWatchingUseCase = ref.watch(stopWatchingMessagesUseCaseProvider);
    ref.watch(listMessagesUseCaseProvider);
    ref.watch(watchNewMessagesUseCaseProvider);
    ref.watch(sendMessageUseCaseProvider);
    ref.watch(updateMessageUseCaseProvider);
    ref.watch(deleteMessageUseCaseProvider);
    ref.watch(pinMessageUseCaseProvider);
    ref.watch(getPinnedMessagesUseCaseProvider);
    ref.watch(messageRepositoryProvider);
    ref.watch(identityStoreProvider);

    String? initialAcsUserId;

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
          initialAcsUserId = me.acsUserId;
        }
      }
    } catch (_) {}

    // 2. Fallback đọc từ token cache
    if (initialAcsUserId == null) {
      final cachedToken =
          ref.read(authTokenRepositoryProvider).getCachedToken(roomId);
      if (cachedToken != null) {
        initialAcsUserId = cachedToken.acsUserId;
      }
    }

    // 2.5 Fallback đọc từ identityStore disk cache
    if (initialAcsUserId == null || initialAcsUserId.isEmpty) {
      initialAcsUserId = _identityStore.getMyAcsUserIdSync(currentUserId);
    }

    // 3. Đã có identity → lưu lại để lần sau khôi phục nhanh (mọi room dùng
    //    chung acsUserId này), tránh phải chờ join-room mới biết mình là ai.
    if (initialAcsUserId != null && initialAcsUserId.isNotEmpty) {
      unawaited(_identityStore.setMyAcsUserId(currentUserId, initialAcsUserId));
    }

    _realtimeSub = _watchNewMessagesUseCase(roomId, threadId).listen((message) {
      if (message.type == MessageType.reactionUpdate) {
        unawaited(refreshReactions());
        return;
      }
      if (message.type == MessageType.messagePinUpdate) {
        updateMessagePin(message.id, message.pin);
        return;
      }
      if (message.type == MessageType.roomPinnedUpdate ||
          message.type == MessageType.roomUnpinnedUpdate) {
        return;
      }
      if (message.type == MessageType.roomUpdatedUpdate ||
          message.type == MessageType.memberJoinedUpdate ||
          message.type == MessageType.memberLeftUpdate ||
          message.type == MessageType.memberRemovedUpdate ||
          (message.type == MessageType.system &&
              (message.metadata?['eventType'] == 'RoomUpdated' ||
                  message.metadata?['eventType'] == 'RoomRoleChanged' ||
                  message.metadata?['eventType'] ==
                      'RoomOwnershipTransferred'))) {
        _handleMemberEventSignal(message);
        return;
      }
      if (message.type == MessageType.system) {
        if (message.content.contains('đã được thêm vào nhóm') ||
            message.content.contains('đã bị xóa khỏi nhóm')) {
          final hasRecentDetailedMessage = _messages.any((m) =>
              m.type == MessageType.system &&
              (m.content.contains('đã thêm') || m.content.contains('đã xóa')) &&
              DateTime.now().difference(m.createdAt).inSeconds < 10);
          if (hasRecentDetailedMessage) return;
        }
      }
      // Tin bị xoá (soft-delete ACS): đánh dấu deletedOn thay vì loại khỏi
      // danh sách — UI hiển thị placeholder "(tin nhắn đã bị xoá)".
      if (message.isDeleted) {
        final i = _messages.indexWhere((m) => m.id == message.id);
        if (i != -1) {
          final updated = [..._messages];
          updated[i] = updated[i].copyWith(
            deletedOn: message.deletedOn ?? DateTime.now(),
          );
          state = state.copyWith(messages: updated);
        } else {
          final list = [..._messages];
          final insertAt =
              list.indexWhere((m) => m.createdAt.isAfter(message.createdAt));
          if (insertAt == -1) {
            list.add(message);
          } else {
            list.insert(insertAt, message);
          }
          state = state.copyWith(messages: list);
        }
        return;
      }
      if (_messages.any((m) => m.id == message.id)) return;
      // Echo của chính tin mình đang gửi dở (optimistic chưa có id thật từ
      // server): thay optimistic bằng tin thật thay vì thêm bản trùng →
      // tránh "lật/giật" do xuất hiện 2 tin giống nhau rồi cuộn lại.
      final pending = _messages
          .where((m) =>
              m.status == MessageDeliveryStatus.sending &&
              m.content == message.content)
          .firstOrNull;
      if (pending != null) {
        final mergedMessage =
            (message.metadata == null || message.metadata!.isEmpty) &&
                    pending.metadata != null
                ? message.copyWith(metadata: pending.metadata)
                : message;
        state = state.copyWith(
          messages: _messages
              .map((m) => m.id == pending.id ? mergedMessage : m)
              .toList(),
        );
        sendReadMessageIfNeeded();
        return;
      }
      // Chèn đúng vị trí theo thời gian để giữ list tăng dần — không sort lại
      // toàn bộ (tránh nhảy thứ tự khi timestamp trùng nhau).
      final list = [..._messages];
      final insertAt =
          list.indexWhere((m) => m.createdAt.isAfter(message.createdAt));
      if (insertAt == -1) {
        list.add(message);
      } else {
        list.insert(insertAt, message);
      }
      state = state.copyWith(messages: list);
      sendReadMessageIfNeeded();

      final isMediaPlaceholder = message.content == '[Hình ảnh]' ||
          message.content == 'Hình ảnh' ||
          message.content == '[Tệp tin]' ||
          message.content == 'Tệp tin';
      if ((message.metadata == null || message.metadata!.isEmpty) &&
          isMediaPlaceholder) {
        unawaited(_enrichMessageMetadata(message.id));
      }
    });

    ref.onDispose(() {
      unawaited(_realtimeSub?.cancel());
      unawaited(stopWatchingUseCase(threadId));
    });

    Future.microtask(() {
      if (ref.mounted) {
        unawaited(_loadHistory());
        unawaited(refreshReactions());
        unawaited(_fetchMembersIfNeeded());
      }
    });

    return ThreadState(myAcsUserId: initialAcsUserId ?? '');
  }

  Future<void> _fetchMembersIfNeeded() async {
    try {
      final members = await ref.read(getMembersUseCaseProvider)(roomId);
      if (ref.mounted && members.isNotEmpty) {
        _cacheParticipantAvatars(members);
        ref.read(conversationListProvider.notifier).updateRoomDetails(
              roomId,
              participants: members,
            );
      }
    } catch (_) {}
  }

  /// Khi nhận event realtime NewMessage từ backend nhưng thiếu metadata (do payload
  /// WebSocket không chứa field Metadata), tự động gọi API lấy lại metadata để
  /// hiển thị ảnh/file ngay trên máy người nhận mà không cần thoát ra vào lại phòng.
  Future<void> _enrichMessageMetadata(String messageId) async {
    try {
      final page =
          await _listMessagesUseCase(roomId: roomId, threadId: threadId);
      final fullMsg = page.items.where((m) => m.id == messageId).firstOrNull;
      if (fullMsg != null &&
          fullMsg.metadata != null &&
          fullMsg.metadata!.isNotEmpty) {
        state = state.copyWith(
          messages: state.messages.map((m) {
            if (m.id == messageId) {
              return m.copyWith(metadata: fullMsg.metadata);
            }
            return m;
          }).toList(),
        );
      }
    } catch (e, st) {
      ChatLogger.error('Enrich message metadata failed for $messageId',
          error: e, stackTrace: st);
    }
  }

  void _handleMemberEventSignal(Message message) {
    final metadata = message.metadata;
    if (metadata == null) return;
    final eventType = metadata['eventType']?.toString();
    final payload = (metadata['payload'] is Map)
        ? (metadata['payload'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    if (eventType == 'MemberRemoved') {
      final removedUserId =
          (metadata['removedUserId'] ?? payload['removedUserId'] ?? '')
              .toString();
      final removedByUserId = (metadata['removedByUserId'] ??
              metadata['actorUserId'] ??
              metadata['actorId'] ??
              payload['removedByUserId'] ??
              payload['actorUserId'] ??
              '')
          .toString();

      final isSelfRemoved = (removedUserId.isNotEmpty &&
          (AcsUserUtils.isSameAcsUser(removedUserId, currentUserId) ||
              (myAcsUserId != null &&
                  AcsUserUtils.isSameAcsUser(removedUserId, myAcsUserId!))));
      if (isSelfRemoved) {
        metadata['isSelf'] = true;
      }

      final rawActorName = metadata['actorName']?.toString() ??
          payload['actorName']?.toString() ??
          metadata['removedByName']?.toString();
      final rawTargetName = metadata['removedUserName']?.toString() ??
          payload['removedUserName']?.toString() ??
          metadata['targetName']?.toString();

      final actorName = (rawActorName != null && rawActorName.isNotEmpty)
          ? rawActorName
          : _getDisplayName(removedByUserId, '');
      final targetName = (rawTargetName != null && rawTargetName.isNotEmpty)
          ? rawTargetName
          : _getDisplayName(removedUserId, '');

      final content = SystemMessageTextBuilder.build(
        eventType: 'MemberRemoved',
        json: metadata,
        payload: payload,
        actorFallback: actorName,
        targetFallback: targetName,
        isSelfRemoved: isSelfRemoved,
      );
      if (content != null) {
        _appendSystemSignalMessage(content, metadata: metadata);
      }
      return;
    }

    if (eventType == 'MemberJoined') {
      final addedByUserId = (metadata['addedByUserId'] ??
              metadata['actorUserId'] ??
              metadata['actorId'] ??
              '')
          .toString();

      final rawActorName = metadata['actorName']?.toString() ??
          metadata['addedByName']?.toString();
      final actorName = (rawActorName != null && rawActorName.isNotEmpty)
          ? rawActorName
          : _getDisplayName(addedByUserId, '');

      final addedUserIds = (metadata['addedUserIds'] as List? ?? const [])
          .map((e) => e.toString())
          .toList();
      final targetNamesFromIds = addedUserIds
          .map((id) => _getDisplayName(id, ''))
          .where((n) => n.isNotEmpty)
          .join(', ');

      final content = SystemMessageTextBuilder.build(
        eventType: 'MemberJoined',
        json: metadata,
        payload: payload,
        actorFallback: actorName,
        joinedUserFallbacks:
            targetNamesFromIds.isNotEmpty ? [targetNamesFromIds] : const [],
      );
      if (content != null) {
        _appendSystemSignalMessage(content);
      }
      return;
    }

    if (eventType == 'MemberLeft') {
      final userId =
          (metadata['userId'] ?? metadata['actorUserId'] ?? '').toString();
      final rawUserName = metadata['actorName']?.toString() ??
          metadata['userName']?.toString() ??
          metadata['targetName']?.toString();

      final userName = (rawUserName != null && rawUserName.isNotEmpty)
          ? rawUserName
          : _getDisplayName(userId, '');

      final content = SystemMessageTextBuilder.build(
        eventType: 'MemberLeft',
        json: metadata,
        payload: payload,
        targetFallback: userName,
      );
      if (content != null) {
        _appendSystemSignalMessage(content);
      }
      return;
    }

    if (eventType == 'RoomRoleChanged') {
      final changedByUserId = (metadata['changedByUserId'] ??
              metadata['actorId'] ??
              metadata['actorUserId'] ??
              metadata['fromUserId'] ??
              '')
          .toString();
      final targetUserId = (metadata['targetUserId'] ??
              metadata['userId'] ??
              metadata['memberUserId'] ??
              metadata['toUserId'] ??
              '')
          .toString();
      final rawActorName = metadata['actorName']?.toString() ??
          metadata['changedByName']?.toString() ??
          metadata['actorDisplayName']?.toString() ??
          metadata['fromUserName']?.toString();
      final rawTargetName = metadata['targetName']?.toString() ??
          metadata['memberName']?.toString() ??
          metadata['userName']?.toString() ??
          metadata['memberUserName']?.toString() ??
          metadata['userDisplayName']?.toString() ??
          metadata['toUserName']?.toString();

      final actorName = (rawActorName != null && rawActorName.trim().isNotEmpty)
          ? rawActorName.trim()
          : _getDisplayName(changedByUserId, '');
      final targetName =
          (rawTargetName != null && rawTargetName.trim().isNotEmpty)
              ? rawTargetName.trim()
              : _getDisplayName(targetUserId, '');

      final content = SystemMessageTextBuilder.build(
        eventType: 'RoomRoleChanged',
        json: metadata,
        payload: payload,
        actorFallback: actorName,
        targetFallback: targetName,
      );
      if (content != null) {
        _appendSystemSignalMessage(content);
      }
      return;
    }

    if (eventType == 'RoomOwnershipTransferred') {
      final actorId = (metadata['transferredByUserId'] ??
              metadata['actorId'] ??
              metadata['fromUserId'] ??
              metadata['changedByUserId'] ??
              '')
          .toString();
      final targetId = (metadata['transferredToUserId'] ??
              metadata['targetUserId'] ??
              metadata['toUserId'] ??
              metadata['newOwnerUserId'] ??
              '')
          .toString();

      final rawActorName = metadata['actorName']?.toString() ??
          metadata['transferredByName']?.toString() ??
          metadata['fromUserName']?.toString();
      final rawTargetName = metadata['targetName']?.toString() ??
          metadata['toUserName']?.toString() ??
          metadata['newOwnerName']?.toString();

      final actorName = (rawActorName != null && rawActorName.isNotEmpty)
          ? rawActorName
          : _getDisplayName(actorId, '');
      final targetName = (rawTargetName != null && rawTargetName.isNotEmpty)
          ? rawTargetName
          : _getDisplayName(targetId, '');

      final content = SystemMessageTextBuilder.build(
        eventType: 'RoomOwnershipTransferred',
        json: metadata,
        payload: payload,
        actorFallback: actorName,
        targetFallback: targetName,
      );
      if (content != null) {
        _appendSystemSignalMessage(content, metadata: metadata);
      }
      return;
    }

    if (eventType == 'RoomUpdated' ||
        message.type == MessageType.roomUpdatedUpdate) {
      final updatedByUserId = (metadata['updatedByUserId'] ??
              metadata['actorId'] ??
              payload['updatedByUserId'] ??
              payload['actorId'] ??
              '')
          .toString();

      final rawActorName = metadata['actorName']?.toString() ??
          payload['actorName']?.toString() ??
          metadata['updatedByName']?.toString() ??
          payload['updatedByName']?.toString();

      final actorName = (rawActorName != null && rawActorName.trim().isNotEmpty)
          ? rawActorName.trim()
          : _getDisplayName(updatedByUserId, '');

      final newRoomName = (metadata['roomName'] ?? payload['roomName'] ?? '').toString().trim();
      final newAvatarUrl = (metadata['avatarUrl'] ?? payload['avatarUrl'] ?? '').toString().trim();

      final conversations = ref.read(conversationListProvider);
      final currentConversation = conversations
          .where((c) => c.id == roomId || c.threadId == threadId)
          .firstOrNull;
      final currentRoomName = currentConversation?.roomName.trim() ?? '';
      final currentAvatarUrl = currentConversation?.avatarUrl?.trim() ?? '';

      final isNameChanged = newRoomName.isNotEmpty &&
          currentRoomName.isNotEmpty &&
          newRoomName != currentRoomName;
      final isAvatarChanged = newAvatarUrl.isNotEmpty &&
          newAvatarUrl != currentAvatarUrl;

      if (isNameChanged) {
        payload['isNameChanged'] = true;
        metadata['isNameChanged'] = true;
      }
      if (isAvatarChanged) {
        payload['isAvatarChanged'] = true;
        metadata['isAvatarChanged'] = true;
      }

      final content = SystemMessageTextBuilder.build(
        eventType: 'RoomUpdated',
        json: metadata,
        payload: payload,
        actorFallback: actorName,
      );
      if (content != null) {
        _appendSystemSignalMessage(content, metadata: metadata);
      }
      return;
    }
  }

  String _getDisplayName(String userId, String fallback) {
    if (userId.isEmpty) return fallback;
    final conversations = ref.read(conversationListProvider);
    final conversation = conversations
        .where((c) => c.id == roomId || c.threadId == threadId)
        .firstOrNull;

    if (conversation != null) {
      final user = conversation.participants.where((p) {
        if (AcsUserUtils.isSameAcsUser(userId, p.id) ||
            AcsUserUtils.isSameAcsUser(userId, p.acsUserId ?? '')) {
          return true;
        }
        if (fallback.trim().isNotEmpty &&
            p.displayName.trim().isNotEmpty &&
            fallback.trim() == p.displayName.trim()) {
          return true;
        }
        return false;
      }).firstOrNull;
      if (user != null && user.displayName.isNotEmpty) {
        return user.displayName;
      }
    }

    for (final m in _messages.reversed) {
      if (m.senderId.isNotEmpty && m.senderDisplayName.isNotEmpty) {
        if (AcsUserUtils.isSameAcsUser(userId, m.senderId)) {
          return m.senderDisplayName;
        }
      }
    }
    return fallback;
  }

  void sendReadMessageIfNeeded() {
    final lastMsg = _messages
        .where((m) =>
            m.id.isNotEmpty &&
            !m.id.startsWith('sys_') &&
            !m.id.startsWith('local-') &&
            m.type != MessageType.system)
        .lastOrNull;
    if (lastMsg != null && lastMsg.id.isNotEmpty) {
      _messageRepository.sendReadMessage(lastMsg.id, roomId: roomId);
    }
  }

  void _appendSystemSignalMessage(String content,
      {Map<String, dynamic>? metadata}) {
    if (_messages.isNotEmpty && _messages.last.content == content) return;

    final sysMsg = MessageModel(
      id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
      threadId: threadId,
      senderId: '',
      senderDisplayName: '',
      content: content,
      type: MessageType.system,
      createdAt: DateTime.now(),
      metadata: metadata,
    );
    state = state.copyWith(messages: [..._messages, sysMsg]);
  }

  Message _enrichSystemMessageContent(Message message) {
    if (message.type != MessageType.system || message.metadata == null)
      return message;
    // Nếu tin nhắn hệ thống đã được format chứa bôi đậm tên (**), giữ nguyên nội dung không ghi đè
    if (message.content.contains('**')) return message;

    final metadata = message.metadata!;
    final eventType = metadata['eventType']?.toString();
    if (eventType == null) return message;

    final payload = (metadata['payload'] is Map)
        ? (metadata['payload'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    final String? actorId = (metadata['actorUserId'] ??
            metadata['actorId'] ??
            metadata['addedByUserId'] ??
            metadata['removedByUserId'] ??
            metadata['changedByUserId'] ??
            metadata['transferredByUserId'] ??
            payload['actorUserId'] ??
            payload['addedByUserId'] ??
            payload['removedByUserId'] ??
            payload['changedByUserId'])
        ?.toString();
    final String? targetId = (metadata['removedUserId'] ??
            metadata['userId'] ??
            metadata['memberUserId'] ??
            metadata['targetUserId'] ??
            metadata['toUserId'] ??
            metadata['transferredToUserId'] ??
            payload['removedUserId'] ??
            payload['targetUserId'] ??
            payload['toUserId'])
        ?.toString();

    final rawActorName = metadata['actorName']?.toString() ??
        metadata['actorDisplayName']?.toString() ??
        metadata['changedByName']?.toString() ??
        metadata['addedByName']?.toString() ??
        metadata['removedByName']?.toString() ??
        metadata['transferredByName']?.toString() ??
        metadata['updatedByName']?.toString() ??
        payload['actorName']?.toString() ??
        payload['actorDisplayName']?.toString() ??
        payload['changedByName']?.toString() ??
        payload['addedByName']?.toString() ??
        payload['removedByName']?.toString();
    final rawTargetName = metadata['removedUserName']?.toString() ??
        metadata['removedUserDisplayName']?.toString() ??
        metadata['targetName']?.toString() ??
        metadata['targetDisplayName']?.toString() ??
        metadata['userName']?.toString() ??
        metadata['memberName']?.toString() ??
        metadata['toUserName']?.toString() ??
        metadata['newOwnerName']?.toString() ??
        payload['removedUserName']?.toString() ??
        payload['removedUserDisplayName']?.toString() ??
        payload['targetName']?.toString() ??
        payload['targetDisplayName']?.toString() ??
        payload['userName']?.toString() ??
        payload['toUserName']?.toString();

    final actorName = (rawActorName != null && rawActorName.trim().isNotEmpty)
        ? rawActorName.trim()
        : (actorId != null && actorId.isNotEmpty
            ? _getDisplayName(actorId, '')
            : '');
    final targetName =
        (rawTargetName != null && rawTargetName.trim().isNotEmpty)
            ? rawTargetName.trim()
            : (targetId != null && targetId.isNotEmpty
                ? _getDisplayName(targetId, '')
                : '');

    final isSelfRemoved = eventType == 'MemberRemoved' &&
        targetId != null &&
        (AcsUserUtils.isSameAcsUser(targetId, currentUserId) ||
            (myAcsUserId != null &&
                AcsUserUtils.isSameAcsUser(targetId, myAcsUserId!)));

    final newContent = SystemMessageTextBuilder.build(
      eventType: eventType,
      json: metadata,
      payload: payload,
      actorFallback: actorName,
      targetFallback: targetName,
      joinedUserFallbacks: targetName.isNotEmpty ? [targetName] : const [],
      isSelfRemoved: isSelfRemoved,
    );

    if (newContent != null && newContent.isNotEmpty) {
      return message.copyWith(content: newContent);
    }
    return message;
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
        final saved = await _identityStore.getMyAcsUserId(currentUserId);
        if (ref.mounted && saved != null && saved.isNotEmpty) {
          state = state.copyWith(myAcsUserId: saved);
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
        state = state.copyWith(myAcsUserId: token.acsUserId);
        ChatLogger.log('myAcsUserId set from join-room: $myAcsUserId '
            'participants=${token.participants.length} '
            'room=$roomId');
        unawaited(_identityStore.setMyAcsUserId(currentUserId, myAcsUserId));
        if (token.participants.isNotEmpty) {
          _cacheParticipantAvatars(token.participants);
          ref
              .read(conversationListProvider.notifier)
              .updateRoomParticipants(roomId, token.participants);
        }
        if (_messages.isEmpty) {
          await _showCachedMessagesIfAny();
        }
      }
    } catch (e, st) {
      ChatLogger.error('join-room/getAccessToken failed',
          error: e, stackTrace: st);
      await _showCachedMessagesIfAny();
    }

    try {
      final result =
          await _listMessagesUseCase(roomId: roomId, threadId: threadId);
      if (!ref.mounted) return;

      final remoteItems = <Message>[];
      for (final m in result.items) {
        final content = m.content.trim();
        final metadata = m.metadata;

        if (content.isEmpty && (metadata == null || metadata.isEmpty)) {
          continue;
        }

        final av = metadata?['senderAvatarUrl'] ??
            metadata?['avatarUrl'] ??
            metadata?['senderAvatar'] ??
            metadata?['userAvatarUrl'];
        if (av != null && isNetworkAvatar(av.toString())) {
          cacheUserAvatar(m.senderId, av.toString());
        }

        remoteItems.add(m);
      }
      final remoteIds = remoteItems.map((m) => m.id).toSet();
      final localExtras = _messages.where((m) {
        if (remoteIds.contains(m.id)) return false;
        final content = m.content.trim();
        if (content.isEmpty && (m.metadata == null || m.metadata!.isEmpty)) {
          return false;
        }
        if (m.type == MessageType.memberJoinedUpdate ||
            m.type == MessageType.memberLeftUpdate ||
            m.type == MessageType.memberRemovedUpdate ||
            m.type == MessageType.roomUpdatedUpdate) {
          return false;
        }
        return true;
      }).toList();
      final mergedItems = remoteItems.map((remoteMsg) {
        var processed = remoteMsg;
        if (processed.type == MessageType.system &&
            processed.metadata != null) {
          processed = _enrichSystemMessageContent(processed);
        }
        final localMsg =
            _messages.where((m) => m.id == remoteMsg.id).firstOrNull;
        if (localMsg != null && localMsg.pin) {
          processed = processed.copyWith(pin: true);
        }
        return processed;
      }).toList();

      state = state.copyWith(
        messages: _chronological([...mergedItems, ...localExtras]),
        cursor: result.cursor,
        clearCursor: result.cursor == null,
        hasMore: result.hasMore,
      );
    } catch (e, st) {
      ChatLogger.error('Error loading messages from remote',
          error: e, stackTrace: st);
      if (!ref.mounted) return;
    } finally {
      unawaited(_loadPinnedMessages());
      if (ref.mounted) {
        state = state.copyWith(historyLoaded: true);
        sendReadMessageIfNeeded();
      }
    }
  }

  /// Hiện cache nếu có và state đang trống — dùng chung cho các nhánh
  /// "đã có identity" và "join chậm/fail". Chỉ render khi biết myAcsUserId
  /// để không vẽ tin sai phía.
  Future<void> _showCachedMessagesIfAny() async {
    try {
      final cached = await _messageRepository.getCachedMessages(threadId);
      final visible = cached.where((m) {
        final content = m.content.trim();
        if (content.isEmpty && (m.metadata == null || m.metadata!.isEmpty)) {
          return false;
        }
        if (m.type == MessageType.memberJoinedUpdate ||
            m.type == MessageType.memberLeftUpdate ||
            m.type == MessageType.memberRemovedUpdate ||
            m.type == MessageType.roomUpdatedUpdate) {
          return false;
        }
        return true;
      }).toList();
      if (ref.mounted && visible.isNotEmpty && _messages.isEmpty) {
        state = state.copyWith(
          messages: _chronological(visible),
          historyLoaded: true,
        );
        sendReadMessageIfNeeded();
      }
    } catch (_) {}
  }

  /// Lấy danh sách tin ghim từ BE rồi:
  /// 1. Lưu vào `state.pinnedMessages` — banner ở đầu màn hình luôn hiện được kể cả khi
  ///    tin ghim chưa được load (nằm ở trang cũ hơn).
  /// 2. Gắn cờ `pin` cho các tin đang hiển thị có id khớp.
  Future<void> _loadPinnedMessages() async {
    try {
      final pinned = await _getPinnedMessagesUseCase(roomId);
      if (!ref.mounted) return;
      final pinnedIds = <String>{for (final p in pinned) p.messageId};
      state = state.copyWith(
        pinnedMessages: pinned,
        messages: [
          for (final m in _messages) m.copyWith(pin: pinnedIds.contains(m.id)),
        ],
      );
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
    if (state.cursor == null || state.isLoadingOlder) return;
    if (!(ref.read(isOnlineProvider).value ?? true)) return;

    state = state.copyWith(isLoadingOlder: true);
    try {
      final result = await _listMessagesUseCase(
          roomId: roomId, threadId: threadId, cursor: state.cursor);
      if (!ref.mounted) return;
      final existingIds = _messages.map((m) => m.id).toSet();
      final visible =
          result.items.where((m) => !existingIds.contains(m.id)).toList();
      state = state.copyWith(
        messages: _chronological([...visible, ..._messages]),
        cursor: result.cursor,
        clearCursor: result.cursor == null,
        hasMore: result.hasMore,
        isLoadingOlder: false,
      );
    } catch (e, st) {
      ChatLogger.error('Error loading older messages',
          error: e, stackTrace: st);
      if (ref.mounted) {
        state = state.copyWith(isLoadingOlder: false);
      }
    }
  }

  bool get isLoadingOlder => state.isLoadingOlder;

  bool get hasMore => state.hasMore;

  bool get hasReachedEnd => !state.hasMore;

  bool get historyLoaded => state.historyLoaded;

  /// Tải lại trang tin mới nhất sau khi quay về từ màn hình quản lý phòng.
  /// Native realtime hiện chưa forward event participantAdded/Removed.
  Future<void> refreshLatest() async {
    try {
      final result =
          await _listMessagesUseCase(roomId: roomId, threadId: threadId);
      if (!ref.mounted) return;
      final byId = <String, Message>{
        for (final message in _messages) message.id: message,
      };
      for (final message in result.items) {
        if (message.type == MessageType.system &&
            byId.values.any((old) =>
                old.type == MessageType.system &&
                old.content == message.content &&
                old.createdAt.difference(message.createdAt).abs() <
                    const Duration(minutes: 2))) {
          continue;
        }
        final old = byId[message.id];
        byId[message.id] =
            old != null && old.pin ? message.copyWith(pin: true) : message;
      }
      state = state.copyWith(
        messages: _chronological(byId.values),
        cursor: result.cursor,
        clearCursor: result.cursor == null,
        hasMore: result.hasMore,
      );
    } catch (e, st) {
      ChatLogger.error('Error refreshing latest messages',
          error: e, stackTrace: st);
    }
  }

  void addSystemMessage(String content) {
    final message = Message(
      id: 'local-system-${DateTime.now().microsecondsSinceEpoch}',
      threadId: threadId,
      senderId: '',
      senderDisplayName: '',
      content: content,
      type: MessageType.system,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(messages: _chronological([..._messages, message]));
  }

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

  Future<void> sendMessage(
    String content, {
    Map<String, dynamic>? metaData,
  }) async {
    var finalMetaData = metaData;
    if (finalMetaData == null) {
      final urlMatch = RegExp(r'(https?://[^\s<]+)').firstMatch(content);
      if (urlMatch != null) {
        final linkUrl = urlMatch.group(0)!;
        final previewData = await LinkPreviewFetcher.fetch(linkUrl);
        finalMetaData = previewData.toJson();
      }
    }

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
      metadata: finalMetaData,
    );
    state = state.copyWith(messages: [..._messages, optimistic]);

    try {
      final sent = await _sendMessageUseCase(
        roomId: roomId,
        threadId: threadId,
        content: content,
        metaData: finalMetaData,
      );
      if (!ref.mounted) return;
      // Thay optimistic bằng tin thật, đồng thời loại bản trùng cùng id
      // (nếu echo realtime đã được chèn vào trước đó) để không hiện 2 tin
      // giống nhau. Tin vừa gửi là mới nhất → append cuối giữ nguyên thứ tự.
      final deduped = _messages
          .where((m) => m.id != optimisticId && m.id != sent.id)
          .toList();
      state = state.copyWith(messages: [...deduped, sent]);
      // Cập nhật tin cuối + đẩy room lên đầu danh sách chat gần đây.
      ref
          .read(conversationListProvider.notifier)
          .updateLastMessage(threadId, sent);
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(
        messages: _messages
            .map((m) => m.id == optimisticId
                ? m.copyWith(status: MessageDeliveryStatus.failed)
                : m)
            .toList(),
      );
    }
  }

  MessageMediaUploadService? _uploadServiceInstance;
  MessageMediaUploadService get _uploadService =>
      _uploadServiceInstance ??= MessageMediaUploadService(
        ref: ref,
        roomId: roomId,
        sendMessage: sendMessage,
      );

  /// Tải các hình ảnh được chọn lên qua Azure Blob SAS URL và gửi tin nhắn hình ảnh.
  Future<void> sendImages(
    List<({String path, String fileName})> imageFiles,
  ) =>
      _uploadService.sendImages(imageFiles);

  /// Tải các tệp tài liệu được chọn lên qua Azure Blob SAS URL và gửi tin nhắn tệp.
  Future<void> sendFiles(
    List<({String path, String fileName})> fileItems,
  ) =>
      _uploadService.sendFiles(fileItems);

  /// Tải video được chọn lên qua Azure Blob SAS URL và gửi tin nhắn video.
  Future<void> sendVideos(
    List<({String path, String fileName})> videoItems,
  ) =>
      _uploadService.sendVideos(videoItems);

  void updateMessagePin(String messageId, bool pin) {
    state = state.copyWith(
      messages: _messages
          .map((m) => m.id == messageId ? m.copyWith(pin: pin) : m)
          .toList(),
    );
  }

  /// Sửa nội dung tin nhắn (chỉ tin của mình). Optimistic — cập nhật UI
  /// ngay, nếu BE thất bại thì rollback về nội dung cũ.
  Future<bool> updateMessage(String messageId, String newContent) async {
    final trimmed = newContent.trim();
    if (trimmed.isEmpty) return false;

    final targetMsg = _messages.where((m) => m.id == messageId).firstOrNull;
    final oldContent = targetMsg?.content;
    final existingMetadata = targetMsg?.metadata;

    state = state.copyWith(
      messages: _messages
          .map((m) => m.id == messageId ? m.copyWith(content: trimmed) : m)
          .toList(),
    );

    try {
      final ok = await _updateMessageUseCase(
        roomId: roomId,
        threadId: threadId,
        messageId: messageId,
        content: trimmed,
        metadata: existingMetadata,
      );
      if (!ok && ref.mounted) {
        _revertMessageContent(messageId, oldContent);
      }
      return ok;
    } catch (e, st) {
      ChatLogger.error('update-message failed', error: e, stackTrace: st);
      if (ref.mounted) {
        _revertMessageContent(messageId, oldContent);
      }
      return false;
    }
  }

  void _revertMessageContent(String messageId, String? oldContent) {
    if (oldContent == null) return;
    state = state.copyWith(
      messages: _messages
          .map((m) => m.id == messageId ? m.copyWith(content: oldContent) : m)
          .toList(),
    );
  }

  /// Xoá tin nhắn. Nếu tin đang được ghim thì bỏ ghim trước rồi mới xoá.
  /// Xoá thành công → ẩn tin ngay (cập nhật UI, không cần chờ refresh) và
  /// làm mới banner tin ghim.
  Future<bool> deleteMessage(String messageId) async {
    final target = _messages.where((m) => m.id == messageId).firstOrNull;
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
        state = state.copyWith(
          messages: _messages
              .map((m) =>
                  m.id == messageId ? m.copyWith(deletedOn: DateTime.now()) : m)
              .toList(),
        );
        // Banner ghim có thể chứa tin vừa xoá → cập nhật lại.
        await _loadPinnedMessages();
      }
      return ok;
    } catch (e, st) {
      ChatLogger.error('delete-message failed', error: e, stackTrace: st);
      return false;
    }
  }

  /// Tự động load thêm tin nhắn cũ hơn cho đến khi chứa tin nhắn có [messageId].
  /// Trả về true nếu tìm thấy, false nếu không tìm thấy (hoặc hết lịch sử/quá giới hạn).
  Future<bool> loadUntilMessage({required String messageId}) async {
    if (_messages.any((m) => m.id == messageId)) {
      return true;
    }

    int attempts = 0;
    const maxAttempts = 20;
    final timeout = DateTime.now().add(const Duration(seconds: 10));

    while (attempts < maxAttempts && DateTime.now().isBefore(timeout)) {
      if (state.cursor == null) {
        break;
      }
      if (state.isLoadingOlder) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (_messages.any((m) => m.id == messageId)) return true;
        continue;
      }

      attempts++;
      await loadOlder();

      if (_messages.any((m) => m.id == messageId)) {
        return true;
      }
    }
    return _messages.any((m) => m.id == messageId);
  }
}
