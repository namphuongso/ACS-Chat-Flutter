import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/widgets/chat_dialogs.dart';
import '../providers/thread_providers.dart';

class UploadErrorListener extends ConsumerWidget {
  const UploadErrorListener({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(mediaUploadErrorProvider, (previous, next) {
      final message = next[roomId];
      if (message == null || message.isEmpty) return;
      ref.read(mediaUploadErrorProvider.notifier).clear(roomId);
      showChatToast(
        context,
        message: message,
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
    });
    return const SizedBox.shrink();
  }
}
