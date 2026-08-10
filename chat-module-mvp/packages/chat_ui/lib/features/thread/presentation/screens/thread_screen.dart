import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/offline_banner.dart';
import '../../../../core/utils/avatar_utils.dart';
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
  final _scrollController = ScrollController();
  int _currentPinnedIndex = 0;
  final Map<String, GlobalKey> _messageKeys = {};

  void _scrollToMessage(String messageId, int index, List<Message> currentMessages) {
    final estimatedPosition = (currentMessages.length - 1 - index) * 75.0;
    _scrollController.animateTo(
      estimatedPosition,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final key = _messageKeys[messageId];
        if (key?.currentContext != null) {
          Scrollable.ensureVisible(
            key!.currentContext!,
            alignment: 1.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showMessageMenu(BuildContext context, Message message) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(message.pin
                  ? Icons.pin_drop_outlined
                  : Icons.push_pin_outlined),
              title: Text(message.pin ? 'Bỏ ghim tin nhắn' : 'Ghim tin nhắn'),
              subtitle: Text(message.content,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(sheetContext);
                _togglePin(messenger, message.id, !message.pin);
              },
            ),
          ],
        ),
      ),
    );
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
        final isMsgMe = myId != null && myId.isNotEmpty && normalize(lastMsg.senderId) == normalize(myId);
        final isSending = lastMsg.status == MessageDeliveryStatus.sending;

        if (isMsgMe || isSending) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0.0,
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
          displayAvatar = widget.senderAvatarUrl;
        }
      } else {
        if (isNetworkAvatar(roomAvatar)) {
          displayAvatar = roomAvatar;
        } else if (isNetworkAvatar(otherAvatar)) {
          displayAvatar = otherAvatar;
        } else {
          displayAvatar = widget.senderAvatarUrl;
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
    final pinnedMessage = pinnedMessages.isNotEmpty
        ? pinnedMessages[_currentPinnedIndex]
        : null;

    return Scaffold(
      appBar: AppBar(
        // Không cho Material 3 tint appbar khi content scroll qua bên dưới.
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
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
            icon: const Icon(Icons.phone),
            onPressed: () {
              // Action call UI
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () {
              // Action callvideo UI
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
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
                  _scrollToMessage(id, index, messages);
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
                    final newIndex = newMessages.indexWhere((m) => m.id == id);
                    if (newIndex != -1) {
                      _scrollToMessage(id, newIndex, newMessages);
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
                        icon: const Icon(Icons.list, size: 20, color: Colors.orange),
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
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const Center(child: Text('Chưa có tin nhắn nào'))
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.metrics.extentAfter < 200) {
                            notifier.loadOlder();
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
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
                                      normalizeAcsId(p.acsUserId!) == normSender)
                                  .firstOrNull;
                            }

                            final bool isMe;
                            String? senderAvatar;

                            if (senderMember != null) {
                              isMe = senderMember.id == widget.currentUserId;
                              if (!isMe) {
                                senderAvatar = isNetworkAvatar(senderMember.avatarUrl)
                                    ? senderMember.avatarUrl
                                    : widget.senderAvatarUrl;
                              }
                            } else {
                              isMe = myId != null && myId.isNotEmpty
                                  ? normSender == normalizeAcsId(myId)
                                  : false;
                              senderAvatar = isMe ? null : widget.senderAvatarUrl;
                            }

                            // ListView reverse: index càng nhỏ tin càng mới.
                            // Tin liền trước về thời gian là messages[index+1].
                            // Chuỗi tin liên tiếp cùng 1 người → chỉ tin
                            // đầu tiên (cũ nhất) hiện avatar, các tin sau ẩn.
                            final bool isFollowUpOfSameSender = index + 1 < messages.length &&
                                normSender.isNotEmpty &&
                                normSender ==
                                    normalizeAcsId(
                                        messages[messages.length - 1 - (index + 1)]
                                            .senderId);

                            final messageKey = _messageKeys.putIfAbsent(
                                message.id, () => GlobalKey());
                            return MessageBubble(
                              key: messageKey,
                              message: message,
                              isMe: isMe,
                              senderAvatarUrl: senderAvatar,
                              showSenderAvatar: !isFollowUpOfSameSender,
                              onLongPress: () =>
                                  _showMessageMenu(context, message),
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
                          final position =
                              (messages.length - 1 - msgIndex) * 75.0;
                          _scrollController.animateTo(
                            position,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
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
                              final position =
                                  (newMessages.length - 1 - newIndex) * 75.0;
                              _scrollController.animateTo(
                                position,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
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
