import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'message_bubble.dart';
import 'message_input.dart';

class ThreadScreen extends ConsumerWidget {
  const ThreadScreen({
    super.key,
    required this.threadId,
    required this.title,
    required this.currentUserId,
  });

  final String threadId;
  final String title;
  final String currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(threadMessagesProvider(threadId));
    final notifier = ref.read(threadMessagesProvider(threadId).notifier);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(child: Text('Chưa có tin nhắn nào'))
                : ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      // reverse:true nên đảo index để hiển thị đúng thứ
                      // tự cũ→mới từ dưới lên (mục 6 kế hoạch gốc).
                      final message = messages[messages.length - 1 - index];
                      return MessageBubble(
                        key: ValueKey(message.id),
                        message: message,
                        isMe: message.senderId == currentUserId,
                      );
                    },
                  ),
          ),
          MessageInput(onSend: notifier.sendMessage),
        ],
      ),
    );
  }
}
