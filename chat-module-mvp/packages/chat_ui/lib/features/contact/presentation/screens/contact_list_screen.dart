import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/chat_dialogs.dart';
import '../../../conversation_list/presentation/providers/conversation_providers.dart';
import '../../../shared/presentation/providers/shared_providers.dart';
import '../../../thread/presentation/screens/add_participants_screen.dart';
import '../notifiers/contact_list_notifier.dart';

class ContactListScreen extends ConsumerStatefulWidget {
  const ContactListScreen({
    super.key,
    required this.currentUserId,
    this.onTapContact,
  });

  final String currentUserId;

  /// Ứng dụng chính truyền vào callback này để bắt sự kiện khi nhấn vào 1 người/nhóm.
  final void Function(Conversation conversation)? onTapContact;

  @override
  ConsumerState<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends ConsumerState<ContactListScreen> {
  bool _isMultiSelectMode = false;
  final Set<String> _selectedUserIds = {};
  final Set<ChatUser> _selectedUsers = {};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(contactListNotifierProvider);
    final notifier = ref.read(contactListNotifierProvider.notifier);
    final uiConfig = ref.watch(chatUiConfigProvider);

    return Column(
      children: [
        if (_isMultiSelectMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: (uiConfig.primaryActionColor ??
                    Theme.of(context).colorScheme.primary)
                .withValues(alpha: 0.08),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Đã chọn ${_selectedUserIds.length} người',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: uiConfig.primaryActionColor ??
                        Theme.of(context).colorScheme.primary,
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isMultiSelectMode = false;
                          _selectedUserIds.clear();
                          _selectedUsers.clear();
                        });
                      },
                      child: const Text('Hủy'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _selectedUserIds.isEmpty
                          ? null
                          : () => _showCreateGroupDialog(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: uiConfig.primaryActionColor ??
                            Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Tiếp tục'),
                    ),
                  ],
                )
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SearchField(
            hintText: 'Tìm kiếm danh bạ...',
            onSearch: notifier.search,
            fillColor: uiConfig.searchBarFillColor,
            iconColor: uiConfig.searchBarIconColor,
            textColor: uiConfig.searchBarTextColor,
            hintColor: uiConfig.searchBarHintColor,
          ),
        ),
        Expanded(
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : state.error != null
                  ? Center(child: Text('Lỗi: ${state.error}'))
                  : NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification scrollInfo) {
                        if (scrollInfo is ScrollUpdateNotification) {
                          final extentAfter = scrollInfo.metrics.extentAfter;
                          if (!state.isLoadingMore &&
                              state.hasMore &&
                              extentAfter < 200) {
                            notifier.loadMore();
                          }
                        }
                        return false;
                      },
                      child: RefreshIndicator(
                        color: uiConfig.refreshIndicatorColor,
                        backgroundColor: uiConfig.refreshIndicatorBackgroundColor ?? Colors.white,
                        onRefresh: notifier.loadContacts,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: (_isMultiSelectMode ? 0 : 1) +
                              state.contacts.length +
                              (state.isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            // Khi không ở chế độ chọn nhiều, dòng đầu tiên là nút "Tạo nhóm mới"
                            if (!_isMultiSelectMode && index == 0) {
                              final primary = uiConfig.primaryActionColor ??
                                  Theme.of(context).colorScheme.primary;
                              return Material(
                                color: Colors.transparent,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: primary,
                                    child: const Icon(Icons.group_add,
                                        color: Colors.white),
                                  ),
                                  title: Text(
                                    'Tạo nhóm mới',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: primary),
                                  ),
                                  onTap: _openCreateGroupScreen,
                                ),
                              );
                            }

                            final actualIndex =
                                _isMultiSelectMode ? index : index - 1;

                            if (actualIndex == state.contacts.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            final user = state.contacts[actualIndex];
                            final hasAvatar = isNetworkAvatar(user.avatarUrl);
                            final isSelected =
                                _selectedUserIds.contains(user.id);
                            final primary = uiConfig.primaryActionColor ??
                                Theme.of(context).colorScheme.primary;

                            return Material(
                              color: isSelected
                                  ? primary.withValues(alpha: 0.05)
                                  : Colors.transparent,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFF0F2F5),
                                  backgroundImage: hasAvatar
                                      ? NetworkImage(user.avatarUrl!)
                                      : null,
                                  child: !hasAvatar
                                      ? Text(
                                          user.displayName.isNotEmpty
                                              ? user.displayName[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                title: Text(user.displayName),
                                subtitle: Text(user.email ?? ''),
                                trailing: _isMultiSelectMode
                                    ? Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected
                                              ? primary
                                              : Colors.transparent,
                                          border: Border.all(
                                            color: isSelected
                                                ? primary
                                                : Colors.grey.shade400,
                                            width: 1.8,
                                          ),
                                        ),
                                        child: isSelected
                                            ? const Icon(
                                                Icons.check,
                                                size: 16,
                                                color: Colors.white,
                                              )
                                            : null,
                                      )
                                    : null,
                                onLongPress: () {
                                  if (!_isMultiSelectMode) {
                                    setState(() {
                                      _isMultiSelectMode = true;
                                      _selectedUserIds.add(user.id);
                                      _selectedUsers.add(user);
                                    });
                                  }
                                },
                                onTap: () {
                                  if (_isMultiSelectMode) {
                                    _toggleSelection(user, !isSelected);
                                  } else {
                                    _handleContactTap(context, user);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  void _toggleSelection(ChatUser user, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedUserIds.add(user.id);
        _selectedUsers.add(user);
      } else {
        _selectedUserIds.remove(user.id);
        _selectedUsers.remove(user);
      }
    });
  }

  Future<void> _openCreateGroupScreen() async {
    final selectedUserIds = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddParticipantsScreen(
          currentMembers: [],
          title: 'Tạo nhóm mới',
        ),
      ),
    );

    if (selectedUserIds != null && selectedUserIds.isNotEmpty && mounted) {
      setState(() {
        _selectedUserIds.clear();
        _selectedUserIds.addAll(selectedUserIds);
      });
      _showCreateGroupDialog(context);
    }
  }

  Future<void> _showCreateGroupDialog(BuildContext context) async {
    final groupName = await showChatTextInputDialog(
      context: context,
      config: ref.read(chatUiConfigProvider),
      title: 'Tạo nhóm mới',
      hintText: 'Nhập tên nhóm chat...',
      confirmLabel: 'Tạo',
    );
    if (groupName != null && mounted) _handleCreateGroup(groupName);
  }

  Future<void> _handleCreateGroup(String groupName) async {
    if (widget.onTapContact == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final createGroupUseCase =
          ref.read(createGroupConversationUseCaseProvider);

      // Thêm bản thân vào danh sách thành viên tạo nhóm
      final allParticipantIds =
          {..._selectedUserIds, widget.currentUserId}.toList();

      var conversation = await createGroupUseCase(
        participantIds: allParticipantIds,
        roomName: groupName,
      );

      if (conversation.token != null &&
          conversation.tokenUtcExp != null &&
          conversation.cui != null) {
        ref.read(authTokenRepositoryProvider).cacheToken(
              conversation.id,
              ChatAccessToken(
                token: conversation.token!,
                expiresOn: conversation.tokenUtcExp!,
                acsUserId: conversation.cui!,
              ),
            );
      }

      // Lưu lại danh sách participants hoàn chỉnh trong local cache
      final listNotifier = ref.read(conversationListProvider.notifier);
      listNotifier.addOrUpdateRoom(conversation);

      setState(() {
        _isMultiSelectMode = false;
        _selectedUserIds.clear();
        _selectedUsers.clear();
      });

      if (context.mounted) {
        Navigator.of(context).pop(); // Tắt loading
        widget.onTapContact!(conversation);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Tắt loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể tạo nhóm: $e')),
        );
      }
    }
  }

  Future<void> _handleContactTap(BuildContext context, ChatUser user) async {
    if (widget.onTapContact == null) return;

    // Hiển thị loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final createRoomUseCase =
          ref.read(getOrCreateDirectConversationUseCaseProvider);
      var conversation = await createRoomUseCase(user.id);
      conversation = _enrichWithContact(conversation, user);

      if (conversation.token != null &&
          conversation.tokenUtcExp != null &&
          conversation.cui != null) {
        ref.read(authTokenRepositoryProvider).cacheToken(
              conversation.id,
              ChatAccessToken(
                token: conversation.token!,
                expiresOn: conversation.tokenUtcExp!,
                acsUserId: conversation.cui!,
              ),
            );
      }

      final listNotifier = ref.read(conversationListProvider.notifier);
      listNotifier.addOrUpdateRoom(conversation);

      if (context.mounted) {
        Navigator.of(context).pop(); // Tắt loading
        widget.onTapContact!(conversation);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Tắt loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể tạo phòng: $e')),
        );
      }
    }
  }

  Conversation _enrichWithContact(Conversation conversation, ChatUser contact) {
    final idx = conversation.participants.indexWhere(
      (p) => p.id == contact.id || p.acsUserId == contact.acsUserId,
    );
    if (idx == -1) {
      return conversation.copyWith(
        participants: [
          ...conversation.participants,
          ChatUser(
            id: contact.id,
            displayName: contact.displayName,
            avatarUrl: contact.avatarUrl,
            acsUserId: contact.acsUserId,
          ),
        ],
      );
    }
    final other = conversation.participants[idx];
    if (isNetworkAvatar(other.avatarUrl)) return conversation;
    final patched = [...conversation.participants];
    patched[idx] = ChatUser(
      id: other.id,
      displayName: other.displayName.isNotEmpty
          ? other.displayName
          : contact.displayName,
      avatarUrl: contact.avatarUrl,
      acsUserId: other.acsUserId ?? contact.acsUserId,
      email: other.email ?? contact.email,
    );
    return conversation.copyWith(participants: patched);
  }
}
