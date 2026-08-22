import 'dart:async';

import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../core/widgets/offline_banner.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/chat_dialogs.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../../../../core/chat_route_observer.dart' show chatRouteObserver;
import '../../../../core/chat_ui_config.dart';
import '../../../conversation_list/presentation/providers/conversation_providers.dart';
import '../providers/thread_providers.dart';
import '../../../shared/presentation/providers/connectivity_providers.dart';
import '../widgets/message_action_button.dart';
import '../widgets/reaction_picker_item.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/message_readers_sheet.dart';
import '../widgets/pinned_message_row.dart';
import '../widgets/upload_error_listener.dart';
import '../widgets/upload_progress_banner.dart';
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
  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        roomIdProvider.overrideWithValue(widget.roomId),
        threadIdProvider.overrideWithValue(widget.threadId),
        currentUserIdProvider.overrideWithValue(widget.currentUserId),
      ],
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

class _ThreadScreenContentState extends ConsumerState<_ThreadScreenContent>
    with WidgetsBindingObserver, RouteAware {
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  int _currentPinnedIndex = 0;

  bool _isSearching = false;
  bool _isSearchingDeeper = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  List<Message> _searchResults = [];
  int _currentSearchIndex = -1;
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  bool _showScrollToBottomButton = false;
  int _unreadNewMessagesCount = 0;

  void _highlightMessage(String messageId) {
    _highlightTimer?.cancel();
    setState(() {
      _highlightedMessageId = messageId;
    });
    _highlightTimer = Timer(const Duration(milliseconds: 3000), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _itemPositionsListener.itemPositions.addListener(_updateScrollBottomState);
  }

  void _updateScrollBottomState() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final isAtBottom = positions.any((p) => p.index == 0);
    if (isAtBottom) {
      if (_showScrollToBottomButton || _unreadNewMessagesCount > 0) {
        setState(() {
          _showScrollToBottomButton = false;
          _unreadNewMessagesCount = 0;
        });
      }
    } else {
      if (!_showScrollToBottomButton) {
        setState(() {
          _showScrollToBottomButton = true;
        });
      }
    }

    final notifier = ref.read(threadMessagesProvider.notifier);
    final messageCount = ref.read(threadMessagesProvider).messages.length;
    final maxIndex =
        positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    if (messageCount > 0 &&
        maxIndex >= messageCount - 5 &&
        notifier.hasMore &&
        !notifier.isLoadingOlder) {
      notifier.loadOlder();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      chatRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _highlightTimer?.cancel();
    _itemPositionsListener.itemPositions
        .removeListener(_updateScrollBottomState);
    _searchController.dispose();
    _searchFocusNode.dispose();
    chatRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    try {
      ref.read(messageRepositoryProvider).leaveActiveRoom();
    } catch (_) {}
    FocusManager.instance.primaryFocus?.unfocus();
    super.dispose();
  }

  void _openMessageSearch() {
    setState(() {
      _isSearching = true;
      _searchResults = [];
      _currentSearchIndex = -1;
      _highlightedMessageId = null;
    });
    Future.microtask(() {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeMessageSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _isSearching = false;
      _isSearchingDeeper = false;
      _searchResults = [];
      _currentSearchIndex = -1;
      _highlightedMessageId = null;
    });
  }

  void _onSearchInputChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        _performMessageSearch(query);
      }
    });
  }

  int _searchSequence = 0;

  List<Message> _filterMessages(List<Message> messages, String trimmedQuery) {
    return messages.where((m) {
      if (m.isDeleted) return false;
      final contentMatch = m.content.toLowerCase().contains(trimmedQuery);
      final fileNameMatch = m.metadata != null &&
          (m.metadata!['fileName']
                  ?.toString()
                  .toLowerCase()
                  .contains(trimmedQuery) ??
              false);
      return contentMatch || fileNameMatch;
    }).toList();
  }

  Future<void> _performMessageSearch(String query) async {
    final currentSeq = ++_searchSequence;
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _currentSearchIndex = -1;
        _highlightedMessageId = null;
        _isSearchingDeeper = false;
      });
      return;
    }

    final allMessages = ref.read(threadMessagesProvider).messages;
    var matches = _filterMessages(allMessages, trimmed);

    if (matches.isNotEmpty) {
      setState(() {
        _searchResults = matches;
        _currentSearchIndex = 0;
        _isSearchingDeeper = false;
      });
      _jumpToSearchResult(0);
      return;
    }

    final notifier = ref.read(threadMessagesProvider.notifier);
    if (notifier.hasReachedEnd) {
      setState(() {
        _searchResults = [];
        _currentSearchIndex = -1;
        _highlightedMessageId = null;
        _isSearchingDeeper = false;
      });
      return;
    }

    // Tự động quét sâu thêm vào lịch sử tin nhắn cũ hơn trong background
    setState(() {
      _searchResults = [];
      _currentSearchIndex = -1;
      _highlightedMessageId = null;
      _isSearchingDeeper = true;
    });

    int pagesFetched = 0;
    while (pagesFetched < 8 && !notifier.hasReachedEnd && mounted) {
      if (_searchSequence != currentSeq || !_isSearching) break;

      final prevCount = ref.read(threadMessagesProvider).messages.length;
      await notifier.loadOlder();
      final newCount = ref.read(threadMessagesProvider).messages.length;
      pagesFetched++;

      if (!mounted || _searchSequence != currentSeq || !_isSearching) break;

      final updatedMessages = ref.read(threadMessagesProvider).messages;
      matches = _filterMessages(updatedMessages, trimmed);

      if (matches.isNotEmpty) {
        setState(() {
          _searchResults = matches;
          _currentSearchIndex = 0;
          _isSearchingDeeper = false;
        });
        _jumpToSearchResult(0);
        return;
      }

      if (newCount == prevCount) break;
    }

    if (mounted && _searchSequence == currentSeq) {
      setState(() {
        _isSearchingDeeper = false;
      });
    }
  }

  List<Message> _getVisibleMessages(List<Message> messages) {
    final roomId = ref.read(roomIdProvider);
    final conversation = ref
        .read(conversationListProvider)
        .where((c) => c.id == roomId)
        .firstOrNull;
    final isGroupConversation = conversation?.type == ConversationType.group ||
        (conversation?.participants.length ?? 0) > 2;

    return messages.where((message) {
      if (message.type == MessageType.memberJoinedUpdate ||
          message.type == MessageType.memberLeftUpdate ||
          message.type == MessageType.memberRemovedUpdate ||
          message.type == MessageType.roomUpdatedUpdate ||
          message.type == MessageType.roomPinnedUpdate ||
          message.type == MessageType.roomUnpinnedUpdate ||
          message.type == MessageType.reactionUpdate ||
          message.type == MessageType.messagePinUpdate) {
        return false;
      }
      if (message.content.trim().isEmpty &&
          (message.metadata == null || message.metadata!.isEmpty)) {
        return false;
      }
      if (!isGroupConversation && message.type == MessageType.system) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _jumpToSearchResult(int resultIndex) async {
    if (resultIndex < 0 || resultIndex >= _searchResults.length) return;
    final targetMessage = _searchResults[resultIndex];
    final notifier = ref.read(threadMessagesProvider.notifier);

    var allMessages = ref.read(threadMessagesProvider).messages;
    var visible = _getVisibleMessages(allMessages);
    var index = visible.indexWhere((m) => m.id == targetMessage.id);

    if (index == -1) {
      final found =
          await notifier.loadUntilMessage(messageId: targetMessage.id);
      if (!found || !mounted) return;
      allMessages = ref.read(threadMessagesProvider).messages;
      visible = _getVisibleMessages(allMessages);
      index = visible.indexWhere((m) => m.id == targetMessage.id);
      if (index == -1) return;
    }

    final scrollIndex = visible.length - 1 - index;

    setState(() {
      _currentSearchIndex = resultIndex;
      _highlightedMessageId = targetMessage.id;
    });

    _scrollToMessage(scrollIndex);
  }

  void _navigateSearchPrevious() {
    if (_searchResults.isEmpty) return;
    final nextIndex = (_currentSearchIndex + 1) % _searchResults.length;
    _jumpToSearchResult(nextIndex);
  }

  void _navigateSearchNext() {
    if (_searchResults.isEmpty) return;
    final prevIndex = (_currentSearchIndex - 1 + _searchResults.length) %
        _searchResults.length;
    _jumpToSearchResult(prevIndex);
  }

  static String _formatSearchResultDate(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final mo = date.month.toString().padLeft(2, '0');
    return '$h:$m $d/$mo';
  }

  void _showSearchResultsSheet(BuildContext context) {
    if (_searchResults.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Tìm thấy ${_searchResults.length} tin nhắn',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final msg = _searchResults[index];
                  final isSelected = index == _currentSearchIndex;
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: Colors.orange.shade50,
                    title: Text(
                      msg.senderDisplayName.isNotEmpty
                          ? msg.senderDisplayName
                          : 'Người dùng',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      msg.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: Text(
                      _formatSearchResultDate(msg.createdAt),
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _jumpToSearchResult(index);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didPushNext() {
    // Chuyển sang màn hình khác đè lên (vd: Màn hình chi tiết room / cài đặt phòng / xem ảnh)
    try {
      ref.read(messageRepositoryProvider).leaveActiveRoom();
    } catch (_) {}
  }

  @override
  void didPopNext() {
    // Quay lại màn hình chat từ màn hình chi tiết/cài đặt/dialog
    if (mounted) {
      try {
        final notifier = ref.read(threadMessagesProvider.notifier);
        ref
            .read(messageRepositoryProvider)
            .watchNewMessages(notifier.roomId, notifier.threadId);
        notifier.sendReadMessageIfNeeded();
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      try {
        ref.read(messageRepositoryProvider).leaveActiveRoom();
      } catch (_) {}
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) {
        try {
          final notifier = ref.read(threadMessagesProvider.notifier);
          ref
              .read(messageRepositoryProvider)
              .watchNewMessages(notifier.roomId, notifier.threadId);
          notifier.sendReadMessageIfNeeded();
        } catch (_) {}
      }
    }
  }

  /// Mở cuộc trò chuyện vừa được tạo từ trang tùy chọn phòng
  /// (ví dụ "Tạo cuộc trò chuyện" từ room 1-1).
  Future<void> _openConversation(Conversation conversation) async {
    final otherParticipants = conversation.participants
        .where((participant) => participant.id != widget.currentUserId);
    final title = conversation.roomName.isNotEmpty
        ? conversation.roomName
        : (otherParticipants.isNotEmpty
            ? otherParticipants
                .map((participant) => participant.displayName)
                .join(', ')
            : 'Phòng chat');
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ThreadScreen(
          roomId: conversation.id,
          threadId: conversation.threadId,
          title: title,
          currentUserId: widget.currentUserId,
          senderAvatarUrl: conversation.avatarUrl,
        ),
      ),
    );
  }

  /// Nhảy tới đúng vị trí tin nhắn (banner tin ghim / danh sách tin ghim).
  /// Dùng `ItemScrollController` để scroll chính xác theo [itemIndex] (index
  /// trong builder, `reverse: true` → index 0 là tin mới nhất) — ListView
  /// lazy trước đây phải ước lượng 75px/item + ensureVisible nên nhảy sai.
  void _scrollToMessage(int itemIndex) {
    if (itemIndex < 0) return;
    void doScroll() {
      if (!_itemScrollController.isAttached) return;
      _itemScrollController.scrollTo(
        index: itemIndex,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }

    if (_itemScrollController.isAttached) {
      doScroll();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_itemScrollController.isAttached) {
          doScroll();
        } else {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_itemScrollController.isAttached) {
              doScroll();
            }
          });
        }
      });
    }
  }

  /// Đang ở đáy danh sách tin nhắn (tin mới nhất index 0 đang hiển thị).
  bool get _isAtBottom {
    final positions = _itemPositionsListener.itemPositions.value;
    return positions.any((p) => p.index == 0);
  }

  bool _isCurrentUserCurrentlyRemoved(
    List<Message> messages,
    String currentUserId,
    String? myAcsUserId,
  ) {
    if (messages.isEmpty) return false;

    for (final m in messages.reversed) {
      final metadata = m.metadata;
      final payload = (metadata?['payload'] is Map)
          ? metadata!['payload'] as Map
          : <String, dynamic>{};
      final eventType = metadata?['eventType']?.toString();
      final removedUserId =
          (metadata?['removedUserId'] ?? payload['removedUserId'] ?? '')
              .toString();
      final addedUsers =
          (metadata?['addedUsers'] ?? payload['addedUsers']) as List? ??
              const [];
      final addedUserIds =
          ((metadata?['addedUserIds'] ?? payload['addedUserIds']) as List? ??
                  const [])
              .map((e) => e.toString())
              .toList();

      if (m.type == MessageType.roomDisbanded) {
        return true;
      }

      final isSelfRemoved = metadata?['isSelf'] == true ||
          (eventType == 'MemberRemoved' &&
              removedUserId.isNotEmpty &&
              (AcsUserUtils.isSameAcsUser(removedUserId, currentUserId) ||
                  (myAcsUserId != null &&
                      AcsUserUtils.isSameAcsUser(removedUserId, myAcsUserId))));

      if (isSelfRemoved) {
        return true;
      }

      final isSelfJoined = eventType == 'MemberJoined' &&
          (addedUsers.any((u) =>
                  u is Map &&
                  (AcsUserUtils.isSameAcsUser(
                          (u['userId'] ?? '').toString(), currentUserId) ||
                      (myAcsUserId != null &&
                          AcsUserUtils.isSameAcsUser(
                              (u['userId'] ?? '').toString(), myAcsUserId)))) ||
              addedUserIds.any((id) =>
                  AcsUserUtils.isSameAcsUser(id, currentUserId) ||
                  (myAcsUserId != null &&
                      AcsUserUtils.isSameAcsUser(id, myAcsUserId))));

      if (isSelfJoined) {
        return false;
      }
    }

    return false;
  }

  String? _getSenderAvatar(Message message) {
    try {
      final roomId = ref.read(roomIdProvider);
      final conversation = ref
          .read(conversationListProvider)
          .where((c) => c.id == roomId)
          .firstOrNull;
      final members = conversation?.participants ?? const [];
      final normSender = AcsUserUtils.normalizeAcsId(message.senderId);
      final senderMember = members.where((m) {
        if (m.id == message.senderId) return true;
        if (m.acsUserId != null &&
            AcsUserUtils.normalizeAcsId(m.acsUserId!) == normSender) {
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
        final myAcs = AcsUserUtils.normalizeAcsId(notifier.myAcsUserId ?? '');
        final myUser = AcsUserUtils.normalizeAcsId(widget.currentUserId);
        myReactionCode = reactions
            .where((r) {
              final rId = AcsUserUtils.normalizeAcsId(r.userId);
              return r.userId == widget.currentUserId ||
                  (myAcs.isNotEmpty && rId == myAcs) ||
                  rId == myUser;
            })
            .firstOrNull
            ?.reactionCode;
      }
    } catch (_) {}
    if (!mounted) return;

    final myAcsUserId = notifier.myAcsUserId;
    final normSender = AcsUserUtils.normalizeAcsId(message.senderId);
    final isMe = message.senderId == widget.currentUserId ||
        (myAcsUserId != null &&
            normSender == AcsUserUtils.normalizeAcsId(myAcsUserId));
    final senderAvatar = isMe ? null : _getSenderAvatar(message);

    var hoveredReactionIndex = -1;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black45,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (overlayContext, setOverlayState) {
          Future<void> selectReaction(int index) async {
            if (index < 0 || index >= reactionConfigs.length) return;
            final reaction = reactionConfigs[index];
            final reactionIdToPass =
                (reaction.id != null && reaction.id!.isNotEmpty)
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
            if (!ok) {
              showChatToast(
                this.context,
                message: 'Không thể cập nhật cảm xúc',
                isError: true,
                config: config,
              );
            }
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
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => Navigator.pop(dialogContext),
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
                                            () => hoveredReactionIndex =
                                                safeIndex,
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
                                            ReactionPickerItem(
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
                                              onTap: () =>
                                                  selectReaction(index),
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
                          const SizedBox(
                              height:
                                  80), // Chừa khoảng trống cho BottomSheet phía dưới
                        ],
                      ),
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
                              MessageActionButton(
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
                              MessageActionButton(
                                icon: Icons.edit_outlined,
                                label: 'Sửa tin',
                                isDisabled: !canEdit,
                                onTap: () {
                                  Navigator.pop(dialogContext);
                                  if (canEdit) _editMessage(context, message);
                                },
                              ),
                              MessageActionButton(
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
                              MessageActionButton(
                                icon: Icons.more_horiz_rounded,
                                label: 'Khác',
                                iconColor: primary,
                                onTap: () async {
                                  ChatLogger.log(
                                      '[MessageAction] Tapped Khác option button');
                                  Navigator.pop(dialogContext);
                                  await Future.delayed(
                                      const Duration(milliseconds: 100));
                                  if (!mounted) return;
                                  _showMoreOptionsMenu(context, message);
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

  void _showMoreOptionsMenu(BuildContext context, Message message) {
    final parentContext = context;
    final messenger = ScaffoldMessenger.of(parentContext);
    final config = ref.read(chatUiConfigProvider);
    final primary =
        config.primaryActionColor ?? config.iconColor ?? Colors.blue;
    final roomId = ref.read(roomIdProvider);

    ChatLogger.log(
        '[MessageAction] Opening _showMoreOptionsMenu for messageId=${message.id}, roomId=$roomId');

    showModalBottomSheet<void>(
      context: parentContext,
      useRootNavigator: true,
      backgroundColor: config.surfaceColor ?? Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(
                  message.pin
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  color: primary,
                ),
                title: Text(message.pin ? 'Bỏ ghim tin nhắn' : 'Ghim tin nhắn'),
                onTap: () {
                  ChatLogger.log('[MessageAction] Tapped Ghim/Bỏ ghim option');
                  Navigator.pop(sheetContext);
                  _togglePin(messenger, message.id, !message.pin);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.remove_red_eye_outlined,
                  color: primary,
                ),
                title: const Text('Danh sách người xem'),
                onTap: () async {
                  ChatLogger.log(
                      '[MessageAction] Tapped Danh sách người xem option');
                  Navigator.pop(sheetContext);
                  await Future.delayed(const Duration(milliseconds: 100));
                  if (!parentContext.mounted) {
                    ChatLogger.log(
                        '[MessageAction] parentContext is no longer mounted!');
                    return;
                  }
                  ChatLogger.log(
                      '[MessageAction] Showing MessageReadersSheet for roomId=$roomId, messageId=${message.id}');
                  MessageReadersSheet.show(
                    context: parentContext,
                    roomId: roomId,
                    messageId: message.id,
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
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
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
                      final myAcs = AcsUserUtils.normalizeAcsId(
                          notifier.myAcsUserId ?? '');
                      final myUser =
                          AcsUserUtils.normalizeAcsId(widget.currentUserId);
                      final rId = AcsUserUtils.normalizeAcsId(reaction.userId);
                      final isMeReaction =
                          reaction.userId == widget.currentUserId ||
                              (myAcs.isNotEmpty && rId == myAcs) ||
                              rId == myUser;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: isNetworkAvatar(avatar)
                              ? NetworkImage(avatar!)
                              : null,
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
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey),
                              )
                            : null,
                        onTap: isMeReaction
                            ? () async {
                                Navigator.pop(sheetContext);
                                final ok =
                                    await notifier.reactMessage(message.id, '');
                                if (!mounted) return;
                                showChatToast(
                                  context,
                                  message: ok
                                      ? 'Đã gỡ cảm xúc'
                                      : 'Không thể gỡ cảm xúc',
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
    final messages = ref.watch(threadMessagesProvider).messages;
    final notifier = ref.read(threadMessagesProvider.notifier);
    final roomId = ref.watch(roomIdProvider);
    final myId = notifier.myAcsUserId;
    final isOnline = ref.watch(isOnlineProvider).value ?? true;

    ref.listen<List<Conversation>>(conversationListProvider, (previous, next) {
      if (previous == null || previous.isEmpty) return;
      final roomStillExists = next.any((c) => c.id == roomId);
      if (!roomStillExists && mounted) {
        final route = ModalRoute.of(context);
        if (route != null && route.isCurrent) {
          showChatToast(
            context,
            message: 'Phòng chat đã bị giải tán',
            isError: true,
            config: ref.read(chatUiConfigProvider),
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
        }
      }
    });

    ref.listen<ThreadState>(threadMessagesProvider, (previous, next) {
      final previousMessages = previous?.messages ?? const <Message>[];
      final nextMessages = next.messages;
      if (nextMessages.isEmpty) return;

      final isCurrentlyRemoved = previousMessages.isEmpty
          ? _isCurrentUserCurrentlyRemoved(
              nextMessages, widget.currentUserId, notifier.myAcsUserId)
          : (nextMessages.length > previousMessages.length &&
              _isCurrentUserCurrentlyRemoved(
                nextMessages.sublist(previousMessages.length),
                widget.currentUserId,
                notifier.myAcsUserId,
              ));

      if (isCurrentlyRemoved && mounted) {
        final chatConfig = ref.read(chatUiConfigProvider);
        final isDisbanded =
            nextMessages.any((m) => m.type == MessageType.roomDisbanded);
        showChatToast(
          context,
          message: isDisbanded
              ? 'Phòng chat đã bị giải tán'
              : 'Bạn đã bị xóa khỏi phòng',
          isError: true,
          config: chatConfig,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
        return;
      }

      if (previousMessages.isEmpty) return;
      if (nextMessages.length > previousMessages.length) {
        final lastMsg = nextMessages.last;
        final isBrandNewMessageAtBottom =
            !previousMessages.any((m) => m.id == lastMsg.id);
        if (!isBrandNewMessageAtBottom) {
          // Chỉ là tải lịch sử tin nhắn cũ hơn — không phải tin mới ở đáy.
          return;
        }

        final newCount = nextMessages.length - previousMessages.length;

        final isMsgMe = myId != null &&
            myId.isNotEmpty &&
            AcsUserUtils.normalizeAcsId(lastMsg.senderId) ==
                AcsUserUtils.normalizeAcsId(myId);

        if (isMsgMe) {
          // Tin nhắn do chính mình gửi → tự động cuộn xuống dưới cùng
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_itemScrollController.isAttached) {
              _itemScrollController.scrollTo(
                index: 0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        } else {
          // Tin nhắn từ người khác đến: KHÔNG tự động cuộn nếu đang ở trên!
          // Hiện nút mũi tên xuống kèm số lượng tin nhắn mới chưa đọc.
          if (!_isAtBottom) {
            setState(() {
              _showScrollToBottomButton = true;
              _unreadNewMessagesCount += newCount;
            });
          }
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
    final isGroupConversation = conversation?.type == ConversationType.group ||
        (conversation?.participants.length ?? 0) > 2;
    final visibleMessages = messages.where((message) {
      if (message.type == MessageType.memberJoinedUpdate ||
          message.type == MessageType.memberLeftUpdate ||
          message.type == MessageType.memberRemovedUpdate ||
          message.type == MessageType.roomUpdatedUpdate ||
          message.type == MessageType.roomPinnedUpdate ||
          message.type == MessageType.roomUnpinnedUpdate ||
          message.type == MessageType.reactionUpdate ||
          message.type == MessageType.messagePinUpdate) {
        return false;
      }
      if (message.content.trim().isEmpty &&
          (message.metadata == null || message.metadata!.isEmpty)) {
        return false;
      }
      return true;
    }).toList();

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
      appBar: _isSearching
          ? AppBar(
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              backgroundColor: chatConfig.appBarBackgroundColor,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios,
                    color: chatConfig.iconColor ?? theme.iconTheme.color),
                onPressed: _closeMessageSearch,
              ),
              titleSpacing: 0,
              title: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                cursorColor: Colors.black,
                style: TextStyle(
                  fontSize: 15,
                  color: chatConfig.appBarIconColor ?? Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: 'Tìm tin nhắn...',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: (chatConfig.appBarIconColor ?? Colors.black87)
                        .withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
                onChanged: _onSearchInputChanged,
                onSubmitted: (query) {
                  _searchDebounce?.cancel();
                  _performMessageSearch(query);
                },
              ),
              actions: [
                if (_searchController.text.isNotEmpty) ...[
                  IconButton(
                    icon: Icon(Icons.clear,
                        size: 20,
                        color: chatConfig.iconColor ?? theme.iconTheme.color),
                    onPressed: () {
                      _searchController.clear();
                      _performMessageSearch('');
                    },
                  ),
                  if (_isSearchingDeeper)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: SkeletonBox(width: 36, height: 16, radius: 8),
                      ),
                    ),
                  if (_searchResults.isNotEmpty) ...[
                    GestureDetector(
                      onTap: () => _showSearchResultsSheet(context),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (chatConfig.iconColor ??
                                    theme.iconTheme.color ??
                                    Colors.black87)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_currentSearchIndex + 1}/${_searchResults.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  chatConfig.iconColor ?? theme.iconTheme.color,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Icon(Icons.keyboard_arrow_up,
                          color: chatConfig.iconColor ?? theme.iconTheme.color),
                      tooltip: 'Tin mới hơn',
                      onPressed: _navigateSearchNext,
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Icon(Icons.keyboard_arrow_down,
                          color: chatConfig.iconColor ?? theme.iconTheme.color),
                      tooltip: 'Tin cũ hơn',
                      onPressed: _navigateSearchPrevious,
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ],
            )
          : AppBar(
              // Không cho Material 3 tint appbar khi content scroll qua bên dưới.
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              backgroundColor: chatConfig.appBarBackgroundColor,
              titleSpacing: 0,
              title: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFF0F2F5),
                    backgroundImage: displayAvatar != null
                        ? NetworkImage(displayAvatar)
                        : null,
                    child: displayAvatar == null
                        ? Text(
                            displayTitle.isNotEmpty
                                ? displayTitle[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              actions: [
                // IconButton(
                //   icon: Icon(Icons.phone,
                //       color: chatConfig.iconColor ?? theme.iconTheme.color),
                //   onPressed: () {
                //     // Action call UI
                //   },
                // ),
                // IconButton(
                //   icon: Icon(Icons.videocam,
                //       color: chatConfig.iconColor ?? theme.iconTheme.color),
                //   onPressed: () {
                //     // Action callvideo UI
                //   },
                // ),
                IconButton(
                  icon: Icon(Icons.info_outline,
                      color: chatConfig.iconColor ?? theme.iconTheme.color),
                  onPressed: () async {
                    final result = await Navigator.of(context).push<Object?>(
                      MaterialPageRoute(
                        builder: (_) => RoomSettingsScreen(
                          roomId: roomId,
                          currentUserId: widget.currentUserId,
                          roomType:
                              conversation?.type ?? ConversationType.direct,
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
                        ),
                      ),
                    );
                    if (result == 'open_search' && context.mounted) {
                      _openMessageSearch();
                      return;
                    }
                    if (result is Conversation && context.mounted) {
                      // Room settings trả về conversation mới được tạo
                      // ("Tạo cuộc trò chuyện") — mở luôn cuộc trò chuyện đó.
                      await _openConversation(result);
                      return;
                    }
                    if ((result == true || result == 'room_disbanded') &&
                        context.mounted) {
                      final route = ModalRoute.of(context);
                      if (route != null &&
                          route.isCurrent &&
                          Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                      return;
                    }
                    if (context.mounted) {
                      await ref
                          .read(threadMessagesProvider.notifier)
                          .refreshLatest();
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
                  _highlightMessage(id);
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
                      final newMessages =
                          ref.read(threadMessagesProvider).messages;
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
                  margin: const EdgeInsets.all(10.0),
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
              child: Stack(
                children: [
                  (isLoading || (_isSearchingDeeper && _searchResults.isEmpty))
                      ? const MessageListSkeleton()
                      : visibleMessages.isEmpty
                          ? const Center(
                              child: Text(
                                  'Chưa có tin nhắn — hãy bắt đầu trò chuyện!'))
                          : ScrollablePositionedList.builder(
                              itemScrollController: _itemScrollController,
                              itemPositionsListener: _itemPositionsListener,
                              reverse: true,
                              itemCount: visibleMessages.length +
                                  (notifier.isLoadingOlder ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == visibleMessages.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: SkeletonBox(
                                          width: 120, height: 14, radius: 7),
                                    ),
                                  );
                                }

                                final message = visibleMessages[
                                    visibleMessages.length - 1 - index];

                                String getSenderKey(Message m) {
                                  final normSender =
                                      AcsUserUtils.normalizeAcsId(m.senderId);
                                  if (conversation != null) {
                                    final member =
                                        conversation.participants.where((p) {
                                      if (p.id == m.senderId) return true;
                                      if (p.acsUserId != null &&
                                          AcsUserUtils.normalizeAcsId(
                                                  p.acsUserId!) ==
                                              normSender) {
                                        return true;
                                      }
                                      if (m.senderDisplayName
                                              .trim()
                                              .isNotEmpty &&
                                          p.displayName.trim().isNotEmpty &&
                                          m.senderDisplayName.trim() ==
                                              p.displayName.trim()) {
                                        return true;
                                      }
                                      return false;
                                    }).firstOrNull;
                                    if (member != null) return member.id;
                                  }
                                  return m.senderId;
                                }

                                ChatUser? senderMember;
                                ChatUser? myParticipant;
                                if (conversation != null) {
                                  senderMember =
                                      conversation.participants.where((p) {
                                    return AcsUserUtils.isSameAcsUser(
                                            message.senderId, p.id) ||
                                        AcsUserUtils.isSameAcsUser(
                                            message.senderId,
                                            p.acsUserId ?? '');
                                  }).firstOrNull;

                                  myParticipant =
                                      conversation.participants.where((p) {
                                    return AcsUserUtils.isSameAcsUser(
                                            p.id, widget.currentUserId) ||
                                        (myId != null &&
                                            myId.isNotEmpty &&
                                            AcsUserUtils.isSameAcsUser(
                                                p.acsUserId ?? '', myId));
                                  }).firstOrNull;
                                }

                                final effectiveMyAcsUserId =
                                    (myId != null && myId.isNotEmpty)
                                        ? myId
                                        : myParticipant?.acsUserId;

                                final bool isMe = AcsUserUtils.isSameAcsUser(
                                        message.senderId, widget.currentUserId) ||
                                    (effectiveMyAcsUserId != null &&
                                        AcsUserUtils.isSameAcsUser(
                                            message.senderId,
                                            effectiveMyAcsUserId)) ||
                                    (senderMember != null &&
                                        (AcsUserUtils.isSameAcsUser(
                                                senderMember.id,
                                                widget.currentUserId) ||
                                            (effectiveMyAcsUserId != null &&
                                                AcsUserUtils.isSameAcsUser(
                                                    senderMember.acsUserId ??
                                                        '',
                                                    effectiveMyAcsUserId))));

                                String? senderAvatar;
                                if (!isMe) {
                                  if (senderMember != null &&
                                      isNetworkAvatar(senderMember.avatarUrl)) {
                                    senderAvatar = senderMember.avatarUrl;
                                  } else {
                                    final cached = notifier
                                        .getAvatarUrlForUser(message.senderId);
                                    if (cached != null &&
                                        isNetworkAvatar(cached)) {
                                      senderAvatar = cached;
                                    } else {
                                      final metaAvatar = message
                                              .metadata?['senderAvatarUrl'] ??
                                          message.metadata?['avatarUrl'] ??
                                          message.metadata?['senderAvatar'] ??
                                          message.metadata?['userAvatarUrl'];
                                      if (isNetworkAvatar(
                                          metaAvatar?.toString())) {
                                        senderAvatar = metaAvatar.toString();
                                      } else {
                                        senderAvatar = isGroupConversation
                                            ? null
                                            : widget.senderAvatarUrl;
                                      }
                                    }
                                  }
                                }

                                if (index == 0 && message.id.isNotEmpty) {
                                  final dbg = StringBuffer()
                                    ..write('room=$roomId')
                                    ..write(' senderId=${message.senderId}')
                                    ..write(' normSender=${message.senderId}')
                                    ..write(' myId=$myId')
                                    ..write(
                                        ' currentUserId=${widget.currentUserId}')
                                    ..write(
                                        ' senderMemberId=${senderMember?.id}')
                                    ..write(
                                        ' senderMemberCui=${senderMember?.acsUserId}')
                                    ..write(
                                        ' participants=${conversation?.participants.map((p) => '${p.id}|${p.acsUserId}').join(',')}')
                                    ..write(' isMe=$isMe')
                                    ..write(
                                        ' convFound=${conversation != null}');
                                  ChatLogger.log('thread-screen-isMe $dbg');
                                }
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
                                  isHighlighted:
                                      message.id == _highlightedMessageId,
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
                  if (_showScrollToBottomButton)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            if (_itemScrollController.isAttached) {
                              _itemScrollController.scrollTo(
                                index: 0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            }
                            setState(() {
                              _showScrollToBottomButton = false;
                              _unreadNewMessagesCount = 0;
                            });
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: chatConfig.surfaceColor ?? Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x29000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                              border: Border.all(
                                color: const Color(0xFFEAECF0),
                                width: 1,
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: chatConfig.primaryActionColor ??
                                      const Color(0xFF0787E8),
                                  size: 28,
                                ),
                                if (_unreadNewMessagesCount > 0)
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 16,
                                        minHeight: 16,
                                      ),
                                      child: Text(
                                        _unreadNewMessagesCount > 99
                                            ? '99+'
                                            : '$_unreadNewMessagesCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
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
            UploadProgressBanner(roomId: roomId),
            UploadErrorListener(roomId: roomId),
            if (_isCurrentUserCurrentlyRemoved(
              messages,
              widget.currentUserId,
              notifier.myAcsUserId,
            ))
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: chatConfig.surfaceColor ?? Colors.grey.shade100,
                alignment: Alignment.center,
                child: Text(
                  messages.any((m) => m.type == MessageType.roomDisbanded)
                      ? 'Phòng chat này đã bị giải tán'
                      : 'Bạn không còn ở trong phòng chat này',
                  style: TextStyle(
                    color:
                        chatConfig.secondaryTextColor ?? Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              MessageInput(
                onSend: notifier.sendMessage,
                onSendImages: notifier.sendImages,
                onSendFiles: notifier.sendFiles,
                onSendVideos: notifier.sendVideos,
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
                  child: PinnedMessageRow(
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
                      return PinnedMessageRow(
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
                          _highlightMessage(id);
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
                                  ref.read(threadMessagesProvider).messages;
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
