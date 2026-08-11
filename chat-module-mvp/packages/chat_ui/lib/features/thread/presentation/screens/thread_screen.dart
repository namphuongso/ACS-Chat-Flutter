import 'dart:developer' as developer;

import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../core/widgets/offline_banner.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../../../../core/chat_ui_config.dart';
import '../../../conversation_list/presentation/providers/conversation_providers.dart';
import '../providers/thread_providers.dart';
import '../notifiers/thread_messages_notifier.dart';
import '../../../shared/presentation/providers/connectivity_providers.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';

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

  void _showMessageMenu(BuildContext context, Message message,
      {required bool canEdit, required Offset position}) {
    final messenger = ScaffoldMessenger.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final relative = RelativeRect.fromRect(
      Rect.fromPoints(position, position),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: relative,
      items: [
        if (canEdit)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Sửa tin nhắn'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: 'pin',
          child: ListTile(
            leading: Icon(message.pin
                ? Icons.pin_drop_outlined
                : Icons.push_pin_outlined),
            title: Text(message.pin ? 'Bỏ ghim tin nhắn' : 'Ghim tin nhắn'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (canEdit)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red),
              title: Text(
                'Xoá tin nhắn',
                style: TextStyle(color: Colors.red),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    ).then((action) {
      if (action == null || !context.mounted) return;
      if (action == 'edit') {
        _editMessage(context, message);
      } else if (action == 'pin') {
        _togglePin(messenger, message.id, !message.pin);
      } else if (action == 'delete') {
        _deleteMessage(context, message);
      }
    });
  }

  /// Xoá tin nhắn (chỉ tin của mình). Hỏi xác nhận trước khi xoá — sau khi
  /// xoá thành công tin biến mất ngay (không cần refresh lại lịch sử).
  Future<void> _deleteMessage(BuildContext context, Message message) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xoá tin nhắn?'),
        content: const Text(
          'Tin nhắn này sẽ bị xoá cho tất cả mọi người trong cuộc trò chuyện.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

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

    final newContent = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _EditMessageDialog(initialContent: message.content),
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

  Future<void> _togglePin(
      ScaffoldMessengerState messenger, String messageId, bool pin) async {
    final notifier = ref.read(threadMessagesProvider.notifier);

    notifier.updateMessagePin(messageId, pin);

    try {
      final ok = await ref.read(pinMessageUseCaseProvider)(
        threadId: notifier.threadId,
        messageId: messageId,
        pin: pin,
      );
      if (!messenger.mounted) return;
      if (!ok) {
        notifier.updateMessagePin(messageId, !pin);
        messenger.showSnackBar(SnackBar(
          content: Text(pin ? 'Không thể ghim tin nhắn' : 'Không thể bỏ ghim'),
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text(pin ? 'Đã ghim tin nhắn' : 'Đã bỏ ghim'),
          duration: const Duration(seconds: 1),
        ));
      }
      // Cập nhật banner + cờ pin từ BE (cả máy kia cũng thấy tin ghim).
      await notifier.refreshPinned();
    } catch (_) {
      if (!messenger.mounted) return;
      notifier.updateMessagePin(messageId, !pin);
      messenger.showSnackBar(
          const SnackBar(content: Text('Thao tác ghim thất bại')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(threadMessagesProvider);
    final notifier = ref.read(threadMessagesProvider.notifier);
    final roomId = ref.watch(roomIdProvider);
    final myId = notifier.myAcsUserId;
    final isOnline = ref.watch(isOnlineProvider).value ?? true;

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
          displayAvatar =
              isNetworkAvatar(widget.senderAvatarUrl)
                  ? widget.senderAvatarUrl
                  : null;
        }
      } else {
        if (isNetworkAvatar(roomAvatar)) {
          displayAvatar = roomAvatar;
        } else if (isNetworkAvatar(otherAvatar)) {
          displayAvatar = otherAvatar;
        } else {
          displayAvatar =
              isNetworkAvatar(widget.senderAvatarUrl)
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
            onPressed: () {
              // Action info UI
            },
          ),
        ],
      ),
      body: Column(
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
                  final found = await notifier.loadUntilMessage(messageId: id);
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
                        content: Text('Không tìm thấy tin nhắn hoặc đã bị xóa'),
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
                color: Colors.orange.shade50,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.push_pin, size: 16, color: Colors.orange),
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
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (pinnedMessages.length > 1) ...[
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.list,
                            size: 20, color: Colors.orange),
                        onPressed: () {
                          _showPinnedMessagesList(
                            context,
                            pinnedMessages,
                            notifier,
                            messages,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Icon(Icons.chevron_right,
                        size: 20, color: Colors.orange),
                  ],
                ),
              ),
            ),
          Expanded(
            child: isLoading
                ? const MessageListSkeleton()
                : messages.isEmpty
                    ? const Center(
                        child:
                            Text('Chưa có tin nhắn — hãy bắt đầu trò chuyện!'))
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
                          itemCount: messages.length +
                              (notifier.isLoadingOlder ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == messages.length) {
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
                            final message =
                                messages[messages.length - 1 - index];
                            String normalizeAcsId(String id) {
                              if (id.startsWith('8:acs:')) {
                                return id.substring(6);
                              }
                              return id;
                            }

                            final normSender = normalizeAcsId(message.senderId);

                            ChatUser? senderMember;
                            if (conversation != null) {
                              senderMember = conversation.participants
                                  .where((p) =>
                                      p.acsUserId != null &&
                                      normalizeAcsId(p.acsUserId!) ==
                                          normSender)
                                  .firstOrNull;
                            }

                            final bool isMe;
                            String? senderAvatar;

                            if (senderMember != null) {
                              isMe = senderMember.id == widget.currentUserId;
                              if (!isMe) {
                                senderAvatar =
                                    isNetworkAvatar(senderMember.avatarUrl)
                                        ? senderMember.avatarUrl
                                        : widget.senderAvatarUrl;
                              }
                            } else {
                              isMe = myId != null && myId.isNotEmpty
                                  ? normSender == normalizeAcsId(myId)
                                  : false;
                              senderAvatar =
                                  isMe ? null : widget.senderAvatarUrl;
                            }

                            if (index == 0 && message.id.isNotEmpty) {
                              final dbg = StringBuffer()
                                ..write('room=$roomId')
                                ..write(' senderId=${message.senderId}')
                                ..write(' normSender=$normSender')
                                ..write(' myId=$myId')
                                ..write(' currentUserId=${widget.currentUserId}')
                                ..write(' senderMemberId=${senderMember?.id}')
                                ..write(' senderMemberCui=${senderMember?.acsUserId}')
                                ..write(' participants=${conversation?.participants.map((p) => '${p.id}|${p.acsUserId}').join(',')}')
                                ..write(' isMe=$isMe')
                                ..write(' convFound=${conversation != null}');
                              developer.log('thread-screen-isMe $dbg',
                                  name: 'ChatModule');
                            }

                            // ListView reverse: index càng nhỏ tin càng mới.
                            // Tin liền trước về thời gian là messages[index+1].
                            // Chuỗi tin liên tiếp cùng 1 người → chỉ tin
                            // đầu tiên (cũ nhất) hiện avatar, các tin sau ẩn.
                            final bool isFollowUpOfSameSender = index + 1 <
                                    messages.length &&
                                normSender.isNotEmpty &&
                                normSender ==
                                    normalizeAcsId(messages[
                                            messages.length - 1 - (index + 1)]
                                        .senderId);

                            return MessageBubble(
                              key: ValueKey(message.id),
                              message: message,
                              isMe: isMe,
                              senderAvatarUrl: senderAvatar,
                              showSenderAvatar: !isFollowUpOfSameSender,
                              onLongPressStart: (details) => _showMessageMenu(
                                context,
                                message,
                                canEdit: isMe,
                                position: details.globalPosition,
                              ),
                            );
                          },
                        ),
                      ),
          ),
          MessageInput(onSend: notifier.sendMessage),
        ],
      ),
    );
  }

  void _showPinnedMessagesList(
    BuildContext context,
    List<PinnedMessage> pinnedMessages,
    ThreadMessagesNotifier notifier,
    List<Message> messages,
  ) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Danh sách tin nhắn đã ghim',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: pinnedMessages.length,
                  itemBuilder: (context, index) {
                    final p = pinnedMessages[index];
                    return ListTile(
                      leading: const Icon(Icons.push_pin, color: Colors.orange),
                      title: Text(
                        p.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Người ghim: ${p.creator}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () async {
                        Navigator.pop(sheetContext);

                        setState(() {
                          _currentPinnedIndex = index;
                        });

                        final id = p.messageId;
                        final msgIndex = messages.indexWhere((m) => m.id == id);
                        if (msgIndex != -1) {
                          _scrollToMessage(messages.length - 1 - msgIndex);
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
                            final newMessages =
                                ref.read(threadMessagesProvider);
                            final newIndex =
                                newMessages.indexWhere((m) => m.id == id);
                            if (newIndex != -1) {
                              _scrollToMessage(
                                  newMessages.length - 1 - newIndex);
                            }
                          } else {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Không tìm thấy tin nhắn hoặc đã bị xóa'),
                              ),
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
        );
      },
    );
  }
}

class _EditMessageDialog extends StatefulWidget {
  const _EditMessageDialog({required this.initialContent});

  final String initialContent;

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sửa tin nhắn'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 5,
        decoration: const InputDecoration(
          hintText: 'Nội dung tin nhắn...',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
