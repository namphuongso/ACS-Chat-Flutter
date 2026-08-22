import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../providers/thread_providers.dart';

class MessageReadersSheet extends ConsumerWidget {
  const MessageReadersSheet({
    super.key,
    required this.roomId,
    required this.messageId,
  });

  final String roomId;
  final String messageId;

  static Future<void> show({
    required BuildContext context,
    required String roomId,
    required String messageId,
  }) {
    ChatLogger.log(
        '[MessageReadersSheet] MessageReadersSheet.show called: roomId=$roomId, messageId=$messageId');
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MessageReadersSheet(
        roomId: roomId,
        messageId: messageId,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiConfig = ref.watch(chatUiConfigProvider);
    final primaryColor = uiConfig.primaryActionColor ??
        uiConfig.iconColor ??
        Theme.of(context).primaryColor;
    final surfaceColor = uiConfig.surfaceColor ?? Colors.white;

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DefaultTabController(
        length: 2,
        child: Column(
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Text(
                    'Danh sách người xem',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            TabBar(
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              labelColor: primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: primaryColor,
              tabs: const [
                Tab(text: 'Đã xem'),
                Tab(text: 'Chưa xem'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ReaderListTab(
                    roomId: roomId,
                    messageId: messageId,
                    read: true,
                  ),
                  _ReaderListTab(
                    roomId: roomId,
                    messageId: messageId,
                    read: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderListTab extends ConsumerWidget {
  const _ReaderListTab({
    required this.roomId,
    required this.messageId,
    required this.read,
  });

  final String roomId;
  final String messageId;
  final bool read;

  String _formatReadTime(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    final timeStr =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return timeStr;
    }
    final dateStr =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    if (local.year == now.year) {
      return '$timeStr $dateStr';
    }
    return '$timeStr $dateStr/${local.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = MessageReadersQuery(
      roomId: roomId,
      messageId: messageId,
      read: read,
    );
    final readersAsync = ref.watch(messageReadersProvider(query));

    return readersAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (err, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Không thể tải danh sách',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => ref.invalidate(messageReadersProvider(query)),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
      data: (readers) {
        if (readers.isEmpty) {
          return Center(
            child: Text(
              read ? 'Chưa có người xem' : 'Không có người chưa xem',
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: readers.length,
          itemBuilder: (context, index) {
            final reader = readers[index];
            final hasAvatar = isNetworkAvatar(reader.avatarUrl);
            final initial = reader.contactName.isNotEmpty
                ? reader.contactName[0].toUpperCase()
                : '?';

            return ListTile(
              leading: CircleAvatar(
                backgroundImage:
                    hasAvatar ? NetworkImage(reader.avatarUrl!) : null,
                child: !hasAvatar ? Text(initial) : null,
              ),
              title: Text(
                reader.contactName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: read && reader.readTime != null
                  ? Text(
                      'Đã xem lúc ${_formatReadTime(reader.readTime)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}
