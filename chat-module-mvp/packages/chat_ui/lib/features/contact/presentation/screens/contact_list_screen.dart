import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../conversation_list/presentation/providers/conversation_providers.dart';
import '../../../shared/presentation/providers/shared_providers.dart';
import '../notifiers/contact_list_notifier.dart';

class ContactListScreen extends ConsumerWidget {
  const ContactListScreen({
    super.key,
    this.onTapContact,
  });

  /// Ứng dụng chính truyền vào callback này để bắt sự kiện khi nhấn vào 1 người.
  /// Nếu cung cấp, thư viện chỉ gọi callback và không tự tạo phòng.
  /// Nếu không cung cấp, thư viện sẽ tự động gọi API tạo phòng và cần app
  /// lắng nghe provider hoặc truyền `onRoomCreated` (để đơn giản, ta sẽ gọi
  /// `create-room` ngay tại đây rồi trả về kết quả cho `onTapContact` dạng
  /// `(Conversation)`.
  /// Do đó, ta sẽ sửa signature thành:
  final void Function(Conversation conversation)? onTapContact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(contactListNotifierProvider);
    final notifier = ref.read(contactListNotifierProvider.notifier);
    final uiConfig = ref.watch(chatUiConfigProvider);

    return Column(
      children: [
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
                        onRefresh: notifier.loadContacts,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: state.contacts.length +
                              (state.isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == state.contacts.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            final user = state.contacts[index];
                            final hasAvatar = isNetworkAvatar(user.avatarUrl);
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: hasAvatar
                                    ? NetworkImage(user.avatarUrl!)
                                    : null,
                                child: !hasAvatar
                                    ? Text(user.displayName.isNotEmpty
                                        ? user.displayName[0].toUpperCase()
                                        : '?')
                                    : null,
                              ),
                              title: Text(user.displayName),
                              subtitle: Text(user.email ?? ''),
                              onTap: () =>
                                  _handleContactTap(context, ref, user),
                            );
                          },
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Future<void> _handleContactTap(
      BuildContext context, WidgetRef ref, ChatUser user) async {
    if (onTapContact == null) return;

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
      // Response create-room có thể thiếu avatar/contactName của member (chỉ
      // get-room-chats mới trả đủ) → enrich bằng thông tin người vừa chọn
      // trong danh bạ để avatar/name hiển thị đúng ngay, không cần refresh.
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

      // Thêm room vừa tạo vào danh sách chat gần đây ngay — không phải đợi
      // pull-to-refresh (với điều kiện màn hình danh sách đang tồn tại).
      final listNotifier = ref.read(conversationListProvider.notifier);
      listNotifier.addOrUpdateRoom(conversation);

      if (context.mounted) {
        Navigator.of(context).pop(); // Tắt loading
        onTapContact!(conversation);
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

  /// Điền thông tin (avatar/displayName) của người vừa chọn vào participant
  /// của room mới tạo nếu create-room response trả thiếu.
  Conversation _enrichWithContact(
      Conversation conversation, ChatUser contact) {
    final idx = conversation.participants.indexWhere(
      (p) => p.id == contact.id || p.acsUserId == contact.acsUserId,
    );
    if (idx == -1) {
      // create-room không trả members → thêm member người kia từ danh bạ.
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
