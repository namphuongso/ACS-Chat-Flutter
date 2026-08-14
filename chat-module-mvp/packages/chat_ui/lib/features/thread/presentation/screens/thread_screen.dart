import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../core/widgets/offline_banner.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/chat_dialogs.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../../../../core/chat_ui_config.dart';
import '../../../conversation_list/presentation/providers/conversation_providers.dart';
import '../providers/thread_providers.dart';
import '../notifiers/thread_messages_notifier.dart';
import '../../../shared/presentation/providers/connectivity_providers.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import 'room_settings_screen.dart';

class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.roomId,
    required this.threadId,
    required this.title,
    required this.currentUserId,
    this.senderAvatarUrl,
  });

  final String roomId;
  final String threadId;
  final String title;
  final String currentUserId;

  /// Avatar người gửi (cho tin nhắn của người khác). Fallback chữ cái đầu.
  final String? senderAvatarUrl;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  late final _overrides = [
    roomIdProvider.overrideWithValue(widget.roomId),
    threadIdProvider.overrideWithValue(widget.threadId),
    currentUserIdProvider.overrideWithValue(widget.currentUserId),
    threadMessagesProvider.overrideWith(ThreadMessagesNotifier.new),
  ];

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: _overrides,
      child: _ThreadScreenContent(
        title: widget.title,
        currentUserId: widget.currentUserId,
        senderAvatarUrl: widget.senderAvatarUrl,
      ),
    );
  }
}

class _ThreadScreenContent extends ConsumerStatefulWidget {
  const _ThreadScreenContent({
    required this.title,
    required this.currentUserId,
    this.senderAvatarUrl,
  });

  final String title;
  final String currentUserId;
  final String? senderAvatarUrl;

  @override
  ConsumerState<_ThreadScreenContent> createState() =>
      _ThreadScreenContentState();
}

class _ThreadScreenContentState extends ConsumerState<_ThreadScreenContent> {
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  int _currentPinnedIndex = 0;
  @override
  void initState() {
    super.initState();
  }

  /// Nhảy tới đúng vị trí tin nhắn (banner tin ghim / danh sách tin ghim).
  /// Dùng `ItemScrollController` để scroll chính xác theo [itemIndex] (index
  /// trong builder, `reverse: true` → index 0 là tin mới nhất) — ListView
  /// lazy trước đây phải ước lượng 75px/item + ensureVisible nên nhảy sai.
  void _scrollToMessage(int itemIndex) {
    if (!_itemScrollController.isAttached) return;
    _itemScrollController.scrollTo(
      index: itemIndex,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Đang ở đáy danh sách tin nhắn (tin mới nhất index 0 đang hiển thị).
  bool get _isAtBottom {
    final positions = _itemPositionsListener.itemPositions.value;
    return positions.any((p) => p.index == 0);
  }

  @override
  void dispose() {
    // Đóng bàn phím khi rời khỏi màn hình chat — trước đây back ra ngoài
    // bàn phím vẫn hiện vì TextField bị dispose khiến FocusManager treo.
    FocusManager.instance.primaryFocus?.unfocus();
    super.dispose();
  }

  String _normalizeAcsId(String id) {
    if (id.startsWith('8:acs:')) {
      return id.substring(6);
    }
    return id;
  }

  String? _getSenderAvatar(Message message) {
    try {
      final roomId = ref.read(roomIdProvider);
      final conversation = ref
          .read(conversationListProvider)
          .where((c) => c.id == roomId)
          .firstOrNull;
      final members = conversation?.participants ?? const [];
      final normSender = _normalizeAcsId(message.senderId);
      final senderMember = members.where((m) {
        if (m.id == message.senderId) return true;
        if (m.acsUserId != null &&
            _normalizeAcsId(m.acsUserId!) == normSender) {
          return true;
        }
        return false;
      }).firstOrNull;

      if (senderMember != null) {
        if (senderMember.id != widget.currentUserId) {
          return isNetworkAvatar(senderMember.avatarUrl)
              ? senderMember.avatarUrl
              : widget.senderAvatarUrl;
        }
      } else {
        return widget.senderAvatarUrl;
      }
    } catch (_) {}
    return widget.senderAvatarUrl;
  }

  /// Mở Modal BottomSheet chứa danh sách thả cảm xúc và menu thao tác tin nhắn.
  Future<void> _showMessageActionsSheet(
    BuildContext context,
    Message message, {
    required bool canEdit,
  }) async {
    final config = ref.read(chatUiConfigProvider);
    final messenger = ScaffoldMessenger.of(context);
    final danger = config.dangerColor ?? Colors.redAccent;
    final primary =
        config.primaryActionColor ?? Theme.of(context).colorScheme.primary;
    final notifier = ref.read(threadMessagesProvider.notifier);
    List<ReactionConfig> reactionConfigs = const [];
    String? myReactionCode;
    try {
      final results = await Future.wait([
        notifier.getReactionConfigs(),
        notifier.getMessageReactions(message.id),
      ]);
      reactionConfigs = results[0] as List<ReactionConfig>;
      final reactions = results[1] as List<MessageReaction>;
      final summary = notifier.reactionSummaryFor(message.id);
      myReactionCode = summary?.myReactionCode;
      if (myReactionCode == null || myReactionCode.isEmpty) {
        final myAcs = _normalizeAcsId(notifier.myAcsUserId ?? '');
        final myUser = _normalizeAcsId(widget.currentUserId);
        myReactionCode = reactions.where((r) {
          final rId = _normalizeAcsId(r.userId);
          return r.userId == widget.currentUserId ||
              (myAcs.isNotEmpty && rId == myAcs) ||
              rId == myUser;
        }).firstOrNull?.reactionCode;
      }
    } catch (_) {}
    if (!mounted) return;

    final myAcsUserId = notifier.myAcsUserId;
    final normSender = _normalizeAcsId(message.senderId);
    final isMe = message.senderId == widget.currentUserId ||
        (myAcsUserId != null && normSender == _normalizeAcsId(myAcsUserId));
    final senderAvatar = isMe ? null : _getSenderAvatar(message);

    var hoveredReactionIndex = -1;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black45,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setOverlayState) {
          Future<void> selectReaction(int index) async {
            if (index < 0 || index >= reactionConfigs.length) return;
            final reaction = reactionConfigs[index];
            final reactionIdToPass = (reaction.id != null && reaction.id!.isNotEmpty)
                ? reaction.id!
                : reaction.code;
            final selected = myReactionCode == reaction.code ||
                (reaction.id != null && myReactionCode == reaction.id);
            Navigator.pop(dialogContext);
            var ok = false;
            try {
              ok = await notifier.reactMessage(
                message.id,
                selected ? '' : reactionIdToPass,
              );
            } catch (_) {}
            if (!mounted) return;
            showChatToast(
              this.context,
              message: ok
                  ? (selected ? 'Đã gỡ cảm xúc' : 'Đã thả cảm xúc')
                  : 'Không thể cập nhật cảm xúc',
              isError: !ok,
              config: config,
            );
          }

          return Material(
            color: Colors.transparent,
            child: SafeArea(
              child: Stack(
                children: [
                  // Backdrop tap to dismiss dialog
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(dialogContext),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // 1. Center/Appear Area: Floating Reaction Bar + Target Message Bubble (Nằm ngoài BottomSheet)
                Align(
                  alignment: Alignment.center,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        // Reaction Bar (Khung thả cảm xúc dạng floating pill)
                        if (reactionConfigs.isNotEmpty)
                          Center(
                            child: Material(
                              color: config.surfaceColor ?? Colors.white,
                              elevation: 12,
                              borderRadius: BorderRadius.circular(28),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onHorizontalDragUpdate: (details) {
                                      final index =
                                          (details.localPosition.dx / 44)
                                              .floor();
                                      final safeIndex = index.clamp(
                                        0,
                                        reactionConfigs.length - 1,
                                      );
                                      if (safeIndex != hoveredReactionIndex) {
                                        setOverlayState(
                                          () =>
                                              hoveredReactionIndex = safeIndex,
                                        );
                                      }
                                    },
                                    onHorizontalDragEnd: (_) {
                                      selectReaction(hoveredReactionIndex);
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (var index = 0;
                                            index < reactionConfigs.length;
                                            index++)
                                          _ReactionPickerItem(
                                            reaction: reactionConfigs[index],
                                            isSelected: myReactionCode ==
                                                reactionConfigs[index].code,
                                            isHovered:
                                                hoveredReactionIndex == index,
                                            primaryColor: primary,
                                            onHover: (hovering) {
                                              setOverlayState(() {
                                                hoveredReactionIndex =
                                                    hovering ? index : -1;
                                              });
                                            },
                                            onTap: () => selectReaction(index),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),

                        // Message Bubble (Tin nhắn được chọn nằm ngoài BottomSheet, hiển thị Avatar đầy đủ)
                        IgnorePointer(
                          child: MessageBubble(
                            message: message,
                            isMe: isMe,
                            senderAvatarUrl: senderAvatar,
                            showSenderAvatar: true,
                            reactionSummary:
                                notifier.reactionSummaryFor(message.id),
                          ),
                        ),
                        const SizedBox(height: 80), // Chừa khoảng trống cho BottomSheet phía dưới
                      ],
                    ),
                  ),
                ),

                // 2. Bottom Area: Action Sheet hiển thị dạng BottomSheet ở đáy (Chứa 4 nút icon tròn ban đầu)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Material(
                      color: config.surfaceColor ?? Colors.white,
                      elevation: 12,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _MessageActionButton(
                              icon: Icons.content_copy_rounded,
                              label: 'Sao chép',
                              onTap: () {
                                Navigator.pop(dialogContext);
                                Clipboard.setData(
                                    ClipboardData(text: message.content));
                                if (mounted) {
                                  showChatToast(
                                    context,
                                    message: 'Đã sao chép tin nhắn',
                                    config: config,
                                  );
                                }
                              },
                            ),
                            _MessageActionButton(
                              icon: Icons.edit_outlined,
                              label: 'Sửa tin',
                              isDisabled: !canEdit,
                              onTap: () {
                                Navigator.pop(dialogContext);
                                if (canEdit) _editMessage(context, message);
                              },
                            ),
                            _MessageActionButton(
                              icon: Icons.delete_outline_rounded,
                              label: 'Xoá tin',
                              iconColor:
                                  canEdit ? danger : Colors.grey.shade400,
                              isDisabled: !canEdit,
                              onTap: () {
                                Navigator.pop(dialogContext);
                                if (canEdit) _deleteMessage(context, message);
                              },
                            ),
                            _MessageActionButton(
                              icon: message.pin
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              label: message.pin ? 'Bỏ ghim' : 'Ghim tin',
                              iconColor: primary,
                              onTap: () {
                                Navigator.pop(dialogContext);
                                _togglePin(
                                    messenger, message.id, !message.pin);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      });
    },
  );
  }

  /// Xoá tin nhắn (chỉ tin của mình). Hỏi xác nhận trước khi xoá — sau khi
  /// xoá thành công tin biến mất ngay (không cần refresh lại lịch sử).
  Future<void> _deleteMessage(BuildContext context, Message message) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showChatConfirmDialog(
      context: context,
      config: ref.read(chatUiConfigProvider),
      title: 'Xoá tin nhắn?',
      message:
          'Tin nhắn này sẽ bị xoá cho tất cả mọi người trong cuộc trò chuyện.',
      confirmLabel: 'Xoá',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final ok = await ref
        .read(threadMessagesProvider.notifier)
        .deleteMessage(message.id);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? 'Đã xoá tin nhắn' : 'Không thể xoá tin nhắn'),
      duration: const Duration(seconds: 1),
    ));
  }

  /// Mở dialog sửa tin nhắn — người gửi mới được sửa tin của mình.
  Future<void> _editMessage(BuildContext context, Message message) async {
    final messenger = ScaffoldMessenger.of(context);

    final newContent = await showChatTextInputDialog(
      context: context,
      config: ref.read(chatUiConfigProvider),
      title: 'Sửa tin nhắn',
      hintText: 'Nội dung tin nhắn...',
      initialValue: message.content,
      maxLines: 5,
    );

    if (newContent == null ||
        newContent.isEmpty ||
        newContent == message.content) {
      return;
    }

    final ok = await ref.read(threadMessagesProvider.notifier).updateMessage(
          message.id,
          newContent,
        );
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? 'Đã sửa tin nhắn' : 'Không thể sửa tin nhắn'),
      duration: const Duration(seconds: 1),
    ));
  }

  Future<void> _showReactionDetails(Message message) async {
    final config = ref.read(chatUiConfigProvider);
    final notifier = ref.read(threadMessagesProvider.notifier);
    List<MessageReaction> reactions;
    try {
      reactions = await notifier.getMessageReactions(message.id);
    } catch (_) {
      if (!mounted) return;
      showChatToast(
        context,
        message: 'Không thể tải danh sách cảm xúc',
        isError: true,
        config: config,
      );
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: config.surfaceColor ?? Colors.white,
      builder: (sheetContext) => Material(
        color: config.surfaceColor ?? Colors.white,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.58,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Cảm xúc về tin nhắn',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: reactions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final reaction = reactions[index];
                      final avatar = reaction.avatarUrl;
                      final myAcs = _normalizeAcsId(notifier.myAcsUserId ?? '');
                      final myUser = _normalizeAcsId(widget.currentUserId);
                      final rId = _normalizeAcsId(reaction.userId);
                      final isMeReaction = reaction.userId == widget.currentUserId ||
                          (myAcs.isNotEmpty && rId == myAcs) ||
                          rId == myUser;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              isNetworkAvatar(avatar) ? NetworkImage(avatar!) : null,
                          child: isNetworkAvatar(avatar)
                              ? null
                              : Text(reaction.contactName.isEmpty
                                  ? '?'
                                  : reaction.contactName[0].toUpperCase()),
                        ),
                        title: Text(
                          isMeReaction
                              ? '${reaction.contactName} (Bạn)'
                              : reaction.contactName,
                        ),
                        subtitle: isMeReaction
                            ? const Text(
                                'Nhấn để gỡ cảm xúc',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              )
                            : null,
                        onTap: isMeReaction
                            ? () async {
                                Navigator.pop(sheetContext);
                                final ok = await notifier.reactMessage(message.id, '');
                                if (!mounted) return;
                                showChatToast(
                                  context,
                                  message: ok ? 'Đã gỡ cảm xúc' : 'Không thể gỡ cảm xúc',
                                  isError: !ok,
                                  config: config,
                                );
                              }
                            : null,
                        trailing: reaction.reactionIconUrl.isEmpty
                            ? const Icon(Icons.emoji_emotions_outlined)
                            : Image.network(
                                reaction.reactionIconUrl,
                                width: 30,
                                height: 30,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.emoji_emotions_outlined,
                                ),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _togglePin(
      ScaffoldMessengerState messenger, String messageId, bool pin) async {
    final notifier = ref.read(threadMessagesProvider.notifier);
    PinnedMessage? replacedMessage;

    if (pin) {
      await notifier.refreshPinned();
      if (!mounted || !messenger.mounted) return;
      if (notifier.pinnedMessages.length >= 3) {
        final replacement = await _selectPinnedMessageToReplace(
          context,
          notifier.pinnedMessages,
        );
        if (replacement == null || !mounted) return;

        final removed = await _setMessagePin(
          messenger,
          replacement.messageId,
          false,
          showSuccess: false,
        );
        if (!removed || !mounted) return;
        replacedMessage = replacement;
      }
    }

    final ok = await _setMessagePin(messenger, messageId, pin);
    if (!ok && replacedMessage != null && mounted) {
      await _setMessagePin(
        messenger,
        replacedMessage.messageId,
        true,
        showSuccess: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(threadMessagesProvider);
    final notifier = ref.read(threadMessagesProvider.notifier);
    final roomId = ref.watch(roomIdProvider);
    final myId = notifier.myAcsUserId;
    final isOnline = ref.watch(isOnlineProvider).value ?? true;

    ref.listen<List<Conversation>>(conversationListProvider, (previous, next) {
      if (previous == null || previous.isEmpty) return;
      final roomStillExists = next.any((c) => c.id == roomId);
      if (!roomStillExists && mounted) {
        final route = ModalRoute.of(context);
        if (route != null && route.isCurrent && Navigator.of(context).canPop()) {
          showChatToast(
            context,
            message: 'Bạn đã rời khỏi phòng chat',
            isError: true,
            config: ref.read(chatUiConfigProvider),
          );
          Navigator.of(context).pop();
        }
      }
    });

    ref.listen<List<Message>>(threadMessagesProvider, (previous, next) {
      if (previous == null || previous.isEmpty) return;
      if (next.length > previous.length) {
        final lastMsg = next.last;
        String normalize(String id) {
          if (id.startsWith('8:acs:')) {
            return id.substring(6);
          }
          return id;
        }

        final isMsgMe = myId != null &&
            myId.isNotEmpty &&
            normalize(lastMsg.senderId) == normalize(myId);
        final isSending = lastMsg.status == MessageDeliveryStatus.sending;
        // Tin của mình → luôn cuộn xuống đáy. Tin của người khác → chỉ cuộn
        // khi đang ở gần đáy, không cướp vị trí đọc khi đang xem tin cũ.
        final atBottom = _isAtBottom;

        if ((isMsgMe || isSending) || atBottom) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_itemScrollController.isAttached) {
              _itemScrollController.scrollTo(
                index: 0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    });
    // Loading chỉ dựa trên dữ liệu lịch sử đã load xong chưa — KHÔNG phụ
    // thuộc myId. Trước đây có `&& myId == null` khiến spinner kẹt vô hạn
    // nếu join-room trễ/thất bại (vd mới cài app, chưa có cache).
    final isLoading = messages.isEmpty && !notifier.historyLoaded;

    ref.listen(isOnlineProvider, (previous, next) {
      final wasOffline = previous?.value == false;
      final nowOnline = next.value == true;
      if (wasOffline && nowOnline) {
        notifier.refreshHistory();
      }
    });

    final conversations = ref.watch(conversationListProvider);
    final conversation = conversations.where((c) => c.id == roomId).firstOrNull;
    if (conversation != null) {
      ChatLogger.logRequest(
        'PARTICIPANTS PAYLOAD (${conversation.participants.length} members)',
        roomId,
        body: conversation.participants
            .map((p) => {
                  'id': p.id,
                  'acsUserId': p.acsUserId,
                  'displayName': p.displayName,
                  'avatarUrl': p.avatarUrl,
                })
            .toList(),
      );
    }
    final isGroupConversation = conversation?.type == ConversationType.group ||
        (conversation?.participants.length ?? 0) > 2;
    final visibleMessages = isGroupConversation
        ? messages
        : messages
            .where((message) => message.type != MessageType.system)
            .toList();

    final String displayTitle;
    final String? displayAvatar;

    if (conversation != null) {
      final other = conversation.participants
          .where((p) => p.id != widget.currentUserId)
          .firstOrNull;
      displayTitle =
          (conversation.type == ConversationType.direct && other != null)
              ? other.displayName
              : (conversation.roomName.isNotEmpty
                  ? conversation.roomName
                  : (other?.displayName ?? widget.title));
      final otherAvatar = other?.avatarUrl;
      final roomAvatar = conversation.avatarUrl;
      if (conversation.type == ConversationType.direct && other != null) {
        if (isNetworkAvatar(otherAvatar)) {
          displayAvatar = otherAvatar;
        } else if (isNetworkAvatar(roomAvatar)) {
          displayAvatar = roomAvatar;
        } else {
          displayAvatar = isNetworkAvatar(widget.senderAvatarUrl)
              ? widget.senderAvatarUrl
              : null;
        }
      } else {
        if (isNetworkAvatar(roomAvatar)) {
          displayAvatar = roomAvatar;
        } else if (isNetworkAvatar(otherAvatar)) {
          displayAvatar = otherAvatar;
        } else {
          displayAvatar = isNetworkAvatar(widget.senderAvatarUrl)
              ? widget.senderAvatarUrl
              : null;
        }
      }
    } else {
      displayTitle = widget.title;
      displayAvatar = widget.senderAvatarUrl;
    }

    // Banner tin ghim từ BE — hiện được kể cả khi tin ghim là tin cũ chưa
    // được load (phân trang).
    final pinnedMessages = notifier.pinnedMessages;
    if (_currentPinnedIndex >= pinnedMessages.length) {
      _currentPinnedIndex = 0;
    }
    final pinnedMessage =
        pinnedMessages.isNotEmpty ? pinnedMessages[_currentPinnedIndex] : null;

    final theme = Theme.of(context);
    final chatConfig = ref.watch(chatUiConfigProvider);

    return Scaffold(
      backgroundColor: chatConfig.roomBackgroundColor,
      appBar: AppBar(
        // Không cho Material 3 tint appbar khi content scroll qua bên dưới.
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: chatConfig.appBarBackgroundColor,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage:
                  displayAvatar != null ? NetworkImage(displayAvatar) : null,
              child: displayAvatar == null
                  ? Text(
                      displayTitle.isNotEmpty
                          ? displayTitle[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 14),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.phone,
                color: chatConfig.iconColor ?? theme.iconTheme.color),
            onPressed: () {
              // Action call UI
            },
          ),
          IconButton(
            icon: Icon(Icons.videocam,
                color: chatConfig.iconColor ?? theme.iconTheme.color),
            onPressed: () {
              // Action callvideo UI
            },
          ),
          IconButton(
            icon: Icon(Icons.info_outline,
                color: chatConfig.iconColor ?? theme.iconTheme.color),
            onPressed: () async {
              final leftRoom = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => RoomSettingsScreen(
                    roomId: roomId,
                    currentUserId: widget.currentUserId,
                    roomType: conversation?.type ?? ConversationType.direct,
                    onRoomChanged: (updatedRoom) {
                      ref
                          .read(conversationListProvider.notifier)
                          .updateRoomDetails(
                            updatedRoom.id,
                            roomName: updatedRoom.roomName,
                            avatarUrl: updatedRoom.avatarUrl,
                            participants: updatedRoom.participants,
                          );
                    },
                    onSystemMessage: (content) {
                      ref
                          .read(threadMessagesProvider.notifier)
                          .addSystemMessage(content);
                    },
                  ),
                ),
              );
              if (leftRoom == true && context.mounted) {
                final route = ModalRoute.of(context);
                if (route != null && route.isCurrent && Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
                return;
              }
              if (context.mounted) {
                await ref.read(threadMessagesProvider.notifier).refreshLatest();
              }
            },
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Column(
          children: [
            if (!isOnline) const OfflineBanner(),
            if (pinnedMessage != null)
              GestureDetector(
                onTap: () async {
                  final id = pinnedMessage.messageId;
                  final index = messages.indexWhere((m) => m.id == id);
                  if (index != -1) {
                    _scrollToMessage(messages.length - 1 - index);
                  } else {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Đang tải tin nhắn cũ hơn...'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                    final found =
                        await notifier.loadUntilMessage(messageId: id);
                    if (found) {
                      final newMessages = ref.read(threadMessagesProvider);
                      final newIndex =
                          newMessages.indexWhere((m) => m.id == id);
                      if (newIndex != -1) {
                        _scrollToMessage(newMessages.length - 1 - newIndex);
                      }
                    } else {
                      messenger.showSnackBar(
                        const SnackBar(
                          content:
                              Text('Không tìm thấy tin nhắn hoặc đã bị xóa'),
                        ),
                      );
                    }
                  }

                  if (pinnedMessages.length > 1) {
                    setState(() {
                      _currentPinnedIndex =
                          (_currentPinnedIndex + 1) % pinnedMessages.length;
                    });
                  }
                },
                child: Container(
                  margin: const EdgeInsets.all(6.0),
                  decoration: BoxDecoration(
                    color: chatConfig.pinnedMessageBackgroundColor ??
                        Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6.0),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.push_pin,
                        size: 16,
                        color:
                            chatConfig.pinnedMessageIconColor ?? Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pinnedMessages.length > 1
                              ? 'Ghim [${_currentPinnedIndex + 1}/${pinnedMessages.length}]: ${pinnedMessage.content}'
                              : 'Tin nhắn được ghim: ${pinnedMessage.content}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: chatConfig.pinnedMessageTextColor ??
                                Colors.orange.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (pinnedMessages.isNotEmpty) ...[
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.list,
                            size: 20,
                            color: chatConfig.pinnedMessageIconColor ??
                                Colors.orange,
                          ),
                          onPressed: () {
                            _showPinnedMessagesSheet(
                              context,
                              pinnedMessages,
                              messages,
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color:
                            chatConfig.pinnedMessageIconColor ?? Colors.orange,
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: isLoading
                  ? const MessageListSkeleton()
                  : visibleMessages.isEmpty
                      ? const Center(
                          child: Text(
                              'Chưa có tin nhắn — hãy bắt đầu trò chuyện!'))
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification.metrics.extentAfter < 200) {
                              notifier.loadOlder();
                            }
                            return false;
                          },
                          child: ScrollablePositionedList.builder(
                            itemScrollController: _itemScrollController,
                            itemPositionsListener: _itemPositionsListener,
                            reverse: true,
                            itemCount: visibleMessages.length +
                                (notifier.isLoadingOlder ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == visibleMessages.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }
                              final message = visibleMessages[
                                  visibleMessages.length - 1 - index];
                              String normalizeAcsId(String id) {
                                if (id.startsWith('8:acs:')) {
                                  return id.substring(6);
                                }
                                return id;
                              }

                              String getSenderKey(Message m) {
                                final norm = normalizeAcsId(m.senderId);
                                if (conversation != null) {
                                  final member = conversation.participants.where((p) {
                                    if (p.id == m.senderId || p.id == norm) return true;
                                    if (p.acsUserId != null &&
                                        normalizeAcsId(p.acsUserId!) == norm) {
                                      return true;
                                    }
                                    return false;
                                  }).firstOrNull;
                                  if (member != null) return member.id;
                                }
                                return norm;
                              }

                              final normSender = normalizeAcsId(message.senderId);

                              ChatUser? senderMember;
                              if (conversation != null) {
                                senderMember = conversation.participants.where((p) {
                                  if (p.id == message.senderId || p.id == normSender) {
                                    return true;
                                  }
                                  if (p.acsUserId != null &&
                                      normalizeAcsId(p.acsUserId!) == normSender) {
                                    return true;
                                  }
                                  return false;
                                }).firstOrNull;
                              }

                              final bool isMe;
                              String? senderAvatar;

                              if (senderMember != null) {
                                isMe = senderMember.id == widget.currentUserId ||
                                    (senderMember.acsUserId != null &&
                                        myId != null &&
                                        myId.isNotEmpty &&
                                        normalizeAcsId(senderMember.acsUserId!) ==
                                            normalizeAcsId(myId));
                                if (!isMe) {
                                  senderAvatar =
                                      isNetworkAvatar(senderMember.avatarUrl)
                                          ? senderMember.avatarUrl
                                          : widget.senderAvatarUrl;
                                }
                              } else {
                                isMe = message.senderId == widget.currentUserId ||
                                    normSender == widget.currentUserId ||
                                    (myId != null && myId.isNotEmpty
                                        ? normSender == normalizeAcsId(myId)
                                        : false);
                                senderAvatar =
                                    isMe ? null : widget.senderAvatarUrl;
                              }

                              if (index == 0 && message.id.isNotEmpty) {
                                final dbg = StringBuffer()
                                  ..write('room=$roomId')
                                  ..write(' senderId=${message.senderId}')
                                  ..write(' normSender=$normSender')
                                  ..write(' myId=$myId')
                                  ..write(
                                      ' currentUserId=${widget.currentUserId}')
                                  ..write(' senderMemberId=${senderMember?.id}')
                                  ..write(
                                      ' senderMemberCui=${senderMember?.acsUserId}')
                                  ..write(
                                      ' participants=${conversation?.participants.map((p) => '${p.id}|${p.acsUserId}').join(',')}')
                                  ..write(' isMe=$isMe')
                                  ..write(' convFound=${conversation != null}');
                                developer.log('thread-screen-isMe $dbg',
                                    name: 'ChatModule');
                              }

                              // ListView reverse: index càng nhỏ tin càng mới.
                              // Tin liền trước về thời gian là messages[index+1].
                              // Chuỗi tin liên tiếp cùng 1 người → chỉ tin
                              // đầu tiên (cũ nhất) hiện avatar, các tin sau ẩn.
                              final currentSenderKey = getSenderKey(message);
                              final bool isFollowUpOfSameSender =
                                  index + 1 < visibleMessages.length &&
                                      currentSenderKey.isNotEmpty &&
                                      currentSenderKey ==
                                          getSenderKey(visibleMessages[
                                              visibleMessages.length -
                                                  1 -
                                                  (index + 1)]);

                              return MessageBubble(
                                key: ValueKey(message.id),
                                message: message,
                                isMe: isMe,
                                senderAvatarUrl: senderAvatar,
                                showSenderAvatar: !isFollowUpOfSameSender,
                                reactionSummary:
                                    notifier.reactionSummaryFor(message.id),
                                onReactionTap: () =>
                                    _showReactionDetails(message),
                                onLongPress: () => _showMessageActionsSheet(
                                  context,
                                  message,
                                  canEdit: isMe,
                                ),
                              );
                            },
                          ),
                        ),
            ),
            _UploadProgressBanner(roomId: roomId),
            MessageInput(
              onSend: notifier.sendMessage,
              onSendImages: notifier.sendImages,
              onSendFiles: notifier.sendFiles,
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _setMessagePin(
    ScaffoldMessengerState messenger,
    String messageId,
    bool pin, {
    bool showSuccess = true,
  }) async {
    final notifier = ref.read(threadMessagesProvider.notifier);

    notifier.updateMessagePin(messageId, pin);

    try {
      final ok = await ref.read(pinMessageUseCaseProvider)(
        threadId: notifier.threadId,
        messageId: messageId,
        pin: pin,
      );
      if (!mounted) return false;
      if (!ok) {
        notifier.updateMessagePin(messageId, !pin);
        showChatToast(
          context,
          message: pin ? 'Không thể ghim tin nhắn' : 'Không thể bỏ ghim',
          isError: true,
          config: ref.read(chatUiConfigProvider),
        );
      } else {
        if (showSuccess) {
          showChatToast(
            context,
            message: pin ? 'Đã ghim tin nhắn' : 'Đã bỏ ghim tin nhắn',
            config: ref.read(chatUiConfigProvider),
          );
        }
      }
      await notifier.refreshPinned();
      return ok;
    } catch (_) {
      if (!mounted) return false;
      notifier.updateMessagePin(messageId, !pin);
      showChatToast(
        context,
        message: 'Thao tác ghim thất bại',
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
      return false;
    }
  }

  Future<PinnedMessage?> _selectPinnedMessageToReplace(
    BuildContext context,
    List<PinnedMessage> pinnedMessages,
  ) {
    final config = ref.read(chatUiConfigProvider);
    return showModalBottomSheet<PinnedMessage>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Thay thế tin nhắn đã ghim',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Đã đủ 3 tin. Chọn một tin bên dưới để gỡ và ghim tin mới.',
                style: TextStyle(
                  fontSize: 13,
                  color: config.secondaryTextColor ?? Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              ...pinnedMessages.map(
                (pinned) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PinnedMessageRow(
                    pinnedMessage: pinned,
                    config: config,
                    actionIcon: Icons.swap_horiz_rounded,
                    actionTooltip: 'Thay thế',
                    onAction: () => Navigator.pop(sheetContext, pinned),
                    onTap: () => Navigator.pop(sheetContext, pinned),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPinnedMessagesSheet(
    BuildContext context,
    List<PinnedMessage> pinnedMessages,
    List<Message> messages,
  ) {
    final config = ref.read(chatUiConfigProvider);
    final notifier = ref.read(threadMessagesProvider.notifier);
    final primary =
        config.primaryActionColor ?? Theme.of(context).colorScheme.primary;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: config.surfaceColor ?? Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.push_pin_rounded, size: 20, color: primary),
                    const SizedBox(width: 8),
                    const Text(
                      'Tin nhắn đã ghim',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${pinnedMessages.length}/3',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: pinnedMessages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final p = pinnedMessages[index];
                      return _PinnedMessageRow(
                        pinnedMessage: p,
                        config: config,
                        actionIcon: Icons.close_rounded,
                        actionTooltip: 'Bỏ ghim',
                        actionColor: Colors.grey.shade600,
                        onAction: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await _setMessagePin(
                            messenger,
                            p.messageId,
                            false,
                          );
                          if (ok && sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          setState(() {
                            _currentPinnedIndex = index;
                          });

                          final id = p.messageId;
                          final msgIndex =
                              messages.indexWhere((m) => m.id == id);
                          if (msgIndex != -1) {
                            _scrollToMessage(messages.length - 1 - msgIndex);
                          } else {
                            showChatToast(
                              context,
                              message: 'Đang tải tin nhắn cũ hơn...',
                              config: config,
                            );
                            final found =
                                await notifier.loadUntilMessage(messageId: id);
                            if (found && mounted) {
                              final newMessages =
                                  ref.read(threadMessagesProvider);
                              final newIndex =
                                  newMessages.indexWhere((m) => m.id == id);
                              if (newIndex != -1) {
                                _scrollToMessage(
                                    newMessages.length - 1 - newIndex);
                              }
                            } else if (mounted) {
                              showChatToast(
                                context,
                                message:
                                    'Không tìm thấy tin nhắn hoặc đã bị xóa',
                                isError: true,
                                config: config,
                              );
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PinnedMessageRow extends StatelessWidget {
  const _PinnedMessageRow({
    required this.pinnedMessage,
    required this.config,
    required this.actionIcon,
    required this.actionTooltip,
    required this.onTap,
    required this.onAction,
    this.actionColor,
  });

  final PinnedMessage pinnedMessage;
  final ChatUiConfig config;
  final IconData actionIcon;
  final String actionTooltip;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final Color? actionColor;

  @override
  Widget build(BuildContext context) {
    final secondaryColor = config.secondaryTextColor ?? Colors.grey.shade600;

    return Material(
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pinnedMessage.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pinnedMessage.creator.isEmpty
                          ? 'Tin nhắn đã ghim'
                          : 'Ghim bởi ${pinnedMessage.creator}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: secondaryColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: actionTooltip,
                onPressed: onAction,
                icon: Icon(actionIcon, size: 18),
                color: actionColor ?? secondaryColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionPickerItem extends StatelessWidget {
  const _ReactionPickerItem({
    required this.reaction,
    required this.isSelected,
    required this.isHovered,
    required this.primaryColor,
    required this.onHover,
    required this.onTap,
  });

  final ReactionConfig reaction;
  final bool isSelected;
  final bool isHovered;
  final Color primaryColor;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: Tooltip(
        message: reaction.displayName,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: AnimatedScale(
                scale: isHovered ? 1.45 : 1,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutBack,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 36,
                  height: 36,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.15)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: primaryColor, width: 1.5)
                        : null,
                  ),
                  child: reaction.iconUrl.isEmpty
                      ? const Icon(Icons.emoji_emotions_outlined, size: 24)
                      : Image.network(
                          reaction.iconUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.emoji_emotions_outlined,
                            size: 24,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.isDisabled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final color =
        isDisabled ? Colors.grey.shade400 : (iconColor ?? Colors.black87);

    final bg = (iconColor ?? Colors.grey.shade600)
        .withValues(alpha: isDisabled ? 0.04 : 0.1);

    return InkWell(
      onTap: isDisabled ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDisabled ? Colors.grey.shade400 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadProgressBanner extends ConsumerWidget {
  const _UploadProgressBanner({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(mediaUploadProgressProvider)[roomId];
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    final totalCount = items.length;
    final completedCount = items.where((i) => i.progress >= 1.0).length;
    final overallProgress =
        items.fold<double>(0.0, (sum, i) => sum + i.progress) / totalCount;
    final overallPercent = (overallProgress * 100).toInt().clamp(0, 100);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Đang tải lên $completedCount/$totalCount ảnh',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                '$overallPercent%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final percent = (item.progress * 100).toInt().clamp(0, 100);
                final isDone = item.progress >= 1.0;
                final file = File(item.path);

                return SizedBox(
                  width: 64,
                  height: 64,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: file.existsSync()
                              ? Image.file(file, fit: BoxFit.cover)
                              : Container(
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.image, color: Colors.grey),
                                ),
                        ),
                        Positioned.fill(
                          child: Container(
                            color: isDone ? Colors.black26 : Colors.black54,
                          ),
                        ),
                        Center(
                          child: isDone
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.greenAccent,
                                  size: 28,
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        value: item.progress,
                                        strokeWidth: 2.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(primary),
                                        backgroundColor: Colors.white38,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$percent%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
