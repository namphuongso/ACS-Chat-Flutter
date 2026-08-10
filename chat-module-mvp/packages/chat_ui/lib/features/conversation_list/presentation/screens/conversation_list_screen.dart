import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_route_observer.dart' show chatRouteObserver;
import '../../../../core/utils/avatar_utils.dart';
import '../../../../core/utils/datetime_helper.dart';
import '../../../../core/utils/last_message_preview.dart';
import '../../../../core/widgets/offline_banner.dart';
import '../../../shared/presentation/providers/connectivity_providers.dart';
import '../../../shared/presentation/providers/shared_providers.dart';
import '../providers/conversation_providers.dart';

class ConversationList extends ConsumerStatefulWidget {
  const ConversationList({
    super.key,
    required this.onTapConversation,
    required this.currentUserId,
  });

  final void Function(Conversation conversation) onTapConversation;
  final String currentUserId;

  @override
  ConsumerState<ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends ConsumerState<ConversationList>
    with RouteAware {
  final _scrollController = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      chatRouteObserver.subscribe(this, route);
    }
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    chatRouteObserver.unsubscribe(this);
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scrollController.position.extentAfter < 200) {
      ref.read(conversationListProvider.notifier).loadMore();
    }
  }

  /// Khi quay lại màn hình danh sách (back từ màn hình chat), tự refresh
  /// để hiện tin nhắn mới nhất thay vì phải pull-to-refresh. Tin mới của
  /// máy khác đã được realtime (watchListMessages) cập nhật sẵn.
  @override
  void didPopNext() {
    ref.read(conversationListProvider.notifier).refresh();
  }

  Future<void> _togglePin(Conversation conversation) async {
    final messenger = ScaffoldMessenger.of(context);
    final useCase = ref.read(pinConversationUseCaseProvider);
    final target = !conversation.pin;

    ref
        .read(conversationListProvider.notifier)
        .updateRoomPin(conversation.id, target);

    try {
      final ok = await useCase(conversation.id, target);
      if (!mounted) return;
      if (!ok) {
        ref
            .read(conversationListProvider.notifier)
            .updateRoomPin(conversation.id, conversation.pin);
        messenger.showSnackBar(
          const SnackBar(content: Text('Không thể ghim cuộc trò chuyện')),
        );
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text(target ? 'Đã ghim cuộc trò chuyện' : 'Đã bỏ ghim'),
          duration: const Duration(seconds: 1),
        ));
      }
    } catch (_) {
      if (!mounted) return;
      ref
          .read(conversationListProvider.notifier)
          .updateRoomPin(conversation.id, conversation.pin);
      messenger.showSnackBar(
          const SnackBar(content: Text('Không thể ghim lúc này')));
    }
  }

  void _showConversationMenu(Conversation conversation) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(conversation.pin
                  ? 'Bỏ ghim cuộc trò chuyện'
                  : 'Ghim cuộc trò chuyện'),
              leading: Icon(
                  conversation.pin ? Icons.push_pin_outlined : Icons.push_pin),
              onTap: () {
                Navigator.pop(sheetContext);
                _togglePin(conversation);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationListProvider);
    final notifier = ref.read(conversationListProvider.notifier);
    final isOnline = ref.watch(isOnlineProvider).value ?? true;

    ref.listen(isOnlineProvider, (previous, next) {
      final wasOffline = previous?.value == false;
      final nowOnline = next.value == true;
      if (wasOffline && nowOnline) {
        // Vừa có mạng trở lại → refresh danh sách mới.
        notifier.refresh();
      }
    });

    return Column(
      children: [
        if (!isOnline) const OfflineBanner(),
        Expanded(
          child: conversations.isEmpty
              ? const Center(child: Text('Chưa có cuộc trò chuyện nào'))
              : RefreshIndicator(
                  onRefresh: notifier.refresh,
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      // MVP chỉ direct — participant còn lại là "người kia" (khác
                      // currentUserId). Group sẽ cần logic khác (Đợt 1 roadmap).
                      final other = conversation.participants
                          .where((p) => p.id != widget.currentUserId)
                          .firstOrNull;
                      final title =
                          (conversation.type == ConversationType.direct &&
                                  other != null)
                              ? other.displayName
                              : (conversation.roomName.isNotEmpty
                                  ? conversation.roomName
                                  : (other?.displayName ?? 'Unknown'));
                      final avatarUrl =
                          (conversation.type == ConversationType.direct &&
                                  other != null)
                              ? (isNetworkAvatar(other.avatarUrl)
                                  ? other.avatarUrl
                                  : null)
                              : (isNetworkAvatar(conversation.avatarUrl)
                                  ? conversation.avatarUrl
                                  : (isNetworkAvatar(other?.avatarUrl)
                                      ? other?.avatarUrl
                                      : null));

                      return ListTile(
                        key: ValueKey(conversation.id),
                        leading: CircleAvatar(
                          backgroundImage: avatarUrl != null
                              ? NetworkImage(avatarUrl)
                              : null,
                          child: avatarUrl == null
                              ? Text(title.isNotEmpty
                                  ? title[0].toUpperCase()
                                  : '?')
                              : null,
                        ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          LastMessagePreview.format(conversation),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              conversation.lastMessage != null
                                  ? DateTimeHelper.formatRelative(
                                      conversation.lastMessage!.createdAt)
                                  : '',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (conversation.pin) ...[
                                  const Icon(
                                    Icons.push_pin,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  if (conversation.unreadCount > 0)
                                    const SizedBox(width: 4),
                                ],
                                if (conversation.unreadCount > 0)
                                  CircleAvatar(
                                    radius: 10,
                                    child: Text(
                                      '${conversation.unreadCount}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => widget.onTapConversation(conversation),
                        onLongPress: () => _showConversationMenu(conversation),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
