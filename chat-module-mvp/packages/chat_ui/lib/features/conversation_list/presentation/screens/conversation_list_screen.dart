import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_route_observer.dart' show chatRouteObserver;
import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../../../../core/utils/datetime_helper.dart';
import '../../../../core/utils/last_message_preview.dart';
import '../../../../core/widgets/offline_banner.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/skeleton.dart';
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
  final _searchController = TextEditingController();
  String _keyword = '';

  /// Tên hiển thị của room dùng cho tìm kiếm: direct → tên người kia,
  /// group → roomName (fallback tên participant).
  String _roomTitle(Conversation conversation) {
    final other = conversation.participants
        .where((p) => p.id != widget.currentUserId)
        .firstOrNull;
    return (conversation.type == ConversationType.direct && other != null)
        ? other.displayName
        : (conversation.roomName.isNotEmpty
            ? conversation.roomName
            : (other?.displayName ?? 'Unknown'));
  }

  void _onSearch(String keyword) {
    if (_keyword == keyword) return;
    setState(() => _keyword = keyword);
  }

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
    _searchController.dispose();
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
    final isLoading = ref.watch(conversationListLoadingProvider);
    final notifier = ref.read(conversationListProvider.notifier);
    final isOnline = ref.watch(isOnlineProvider).value ?? true;
    final uiConfig = ref.watch(chatUiConfigProvider);

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
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SearchField(
            hintText: 'Tìm kiếm phòng chat...',
            controller: _searchController,
            onSearch: _onSearch,
            fillColor: uiConfig.searchBarFillColor,
            iconColor: uiConfig.searchBarIconColor,
            textColor: uiConfig.searchBarTextColor,
            hintColor: uiConfig.searchBarHintColor,
          ),
        ),
        Expanded(
          child: isLoading && conversations.isEmpty
              ? const ConversationListSkeleton()
              : conversations.isEmpty && _keyword.isEmpty
                  ? const Center(child: Text('Chưa có cuộc trò chuyện nào'))
                  : RefreshIndicator(
                      color: uiConfig.refreshIndicatorColor,
                      backgroundColor: uiConfig.refreshIndicatorBackgroundColor ?? Colors.white,
                      onRefresh: notifier.refresh,
                      child: Builder(
                        builder: (context) {
                          final filtered = _keyword.isEmpty
                              ? conversations
                              : conversations
                                  .where((c) => _roomTitle(c)
                                      .toLowerCase()
                                      .contains(_keyword.toLowerCase()))
                                  .toList();
                          if (filtered.isEmpty) {
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 48),
                                  child: Center(
                                    child:
                                        Text('Không tìm thấy cuộc trò chuyện'),
                                  ),
                                ),
                              ],
                            );
                          }
                          return ListView.builder(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final conversation = filtered[index];
                              // MVP chỉ direct — participant còn lại là "người kia" (khác
                              // currentUserId). Group sẽ cần logic khác (Đợt 1 roadmap).
                              final other = conversation.participants
                                  .where((p) => p.id != widget.currentUserId)
                                  .firstOrNull;
                              final title = (conversation.type ==
                                          ConversationType.direct &&
                                      other != null)
                                  ? other.displayName
                                  : (conversation.roomName.isNotEmpty
                                      ? conversation.roomName
                                      : (other?.displayName ?? 'Unknown'));
                              final avatarUrl = (conversation.type ==
                                          ConversationType.direct &&
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
                                              conversation
                                                  .lastMessage!.createdAt)
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
                                        if (conversation.pin)
                                          const Icon(
                                            Icons.push_pin,
                                            size: 14,
                                            color: Colors.grey,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                onTap: () =>
                                    widget.onTapConversation(conversation),
                                onLongPress: () =>
                                    _showConversationMenu(conversation),
                              );
                            },
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
