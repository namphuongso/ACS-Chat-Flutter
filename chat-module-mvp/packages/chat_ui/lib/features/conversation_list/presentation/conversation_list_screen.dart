import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConversationList extends ConsumerWidget {
  const ConversationList({
    super.key,
    required this.onTapConversation,
    required this.currentUserId,
  });

  final void Function(Conversation conversation) onTapConversation;
  final String currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationListProvider);
    final notifier = ref.read(conversationListProvider.notifier);

    if (conversations.isEmpty) {
      return const Center(child: Text('Chưa có cuộc trò chuyện nào'));
    }

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView.builder(
        itemCount: conversations.length,
        itemBuilder: (context, index) {
          final conversation = conversations[index];
          // MVP chỉ direct — participant còn lại là "người kia" (khác
          // currentUserId). Group sẽ cần logic khác (Đợt 1 roadmap).
          final other = conversation.participants
              .where((p) => p.id != currentUserId)
              .firstOrNull;

          return ListTile(
            key: ValueKey(conversation.id),
            leading: CircleAvatar(
              backgroundImage:
                  other?.avatarUrl != null ? NetworkImage(other!.avatarUrl!) : null,
              child: other?.avatarUrl == null ? Text(other?.displayName[0] ?? '?') : null,
            ),
            title: Text(other?.displayName ?? 'Unknown'),
            subtitle: Text(
              conversation.lastMessage?.content ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: conversation.unreadCount > 0
                ? CircleAvatar(
                    radius: 10,
                    child: Text(
                      '${conversation.unreadCount}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  )
                : null,
            onTap: () => onTapConversation(conversation),
          );
        },
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
