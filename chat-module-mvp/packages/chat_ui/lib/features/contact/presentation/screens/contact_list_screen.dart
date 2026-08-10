import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/avatar_utils.dart';
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Tìm kiếm danh bạ...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8.0)),
              ),
            ),
            onSubmitted: notifier.search,
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
      final conversation = await createRoomUseCase(user.id);

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
}
