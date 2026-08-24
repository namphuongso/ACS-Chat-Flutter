import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/widgets/chat_dialogs.dart';
import '../notifiers/thread_messages_notifier.dart';
import '../providers/thread_providers.dart';
import 'message_action_button.dart';
import 'message_bubble.dart';
import 'message_readers_sheet.dart';
import 'reaction_picker_item.dart';

/// Widget hiển thị Menu ngữ cảnh và Action Sheet thao tác với tin nhắn (Sao chép, Sửa, Xóa, Ghim, Cảm xúc).
class MessageActionSheet {
  const MessageActionSheet._();

  static Future<void> showMessageContextMenu({
    required BuildContext context,
    required WidgetRef ref,
    required Message message,
    required bool isMe,
    required String? senderAvatar,
    required ThreadMessagesNotifier notifier,
  }) async {
    final config = ref.read(chatUiConfigProvider);
    final primary =
        config.primaryActionColor ?? config.iconColor ?? Colors.blue;
    final danger = config.dangerColor ?? Colors.red;

    List<ReactionConfig> reactionConfigs = const [];
    String? myReactionCode;

    try {
      final results = await Future.wait([
        notifier.getReactionConfigs(),
        notifier.getMessageReactions(message.id),
      ]);
      reactionConfigs = results[0] as List<ReactionConfig>;
      final userReactions = results[1] as List<MessageReaction>;
      final myReaction = userReactions
          .where((r) =>
              AcsUserUtils.isSameAcsUser(r.userId, notifier.currentUserId))
          .firstOrNull;
      myReactionCode = myReaction?.reactionCode;
    } catch (e, st) {
      ChatLogger.error('Failed to load reactions context menu',
          error: e, stackTrace: st);
    }

    if (!context.mounted) return;

    final canEdit = isMe && !message.isDeleted;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) {
        int hoveredReactionIndex = -1;

        return StatefulBuilder(builder: (overlayContext, setOverlayState) {
          Future<void> selectReaction(int index) async {
            if (index < 0 || index >= reactionConfigs.length) return;
            final target = reactionConfigs[index];
            final reactionVal = (target.id != null && target.id!.isNotEmpty)
                ? target.id!
                : target.code;
            final isAlreadySelected = myReactionCode == reactionVal ||
                myReactionCode == target.code ||
                myReactionCode == target.id;
            final codeToSend = isAlreadySelected ? '' : reactionVal;
            Navigator.pop(dialogContext);
            bool ok = false;
            try {
              ok = await notifier.reactMessage(message.id, codeToSend);
            } catch (_) {}
            if (!context.mounted) return;
            if (!ok) {
              showChatToast(
                context,
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
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(dialogContext),
                      child: const SizedBox.expand(),
                    ),
                  ),
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
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                                  if (context.mounted) {
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
                                onTap: () async {
                                  Navigator.pop(dialogContext);
                                  await Future.delayed(
                                      const Duration(milliseconds: 100));
                                  if (!context.mounted) return;
                                  if (canEdit) _editMessage(context, ref, message);
                                },
                              ),
                              MessageActionButton(
                                icon: Icons.delete_outline_rounded,
                                label: 'Xoá tin',
                                iconColor:
                                    canEdit ? danger : Colors.grey.shade400,
                                isDisabled: !canEdit,
                                onTap: () async {
                                  Navigator.pop(dialogContext);
                                  await Future.delayed(
                                      const Duration(milliseconds: 100));
                                  if (!context.mounted) return;
                                  if (canEdit) _deleteMessage(context, ref, message);
                                },
                              ),
                              MessageActionButton(
                                icon: Icons.more_horiz_rounded,
                                label: 'Khác',
                                iconColor: primary,
                                onTap: () async {
                                  Navigator.pop(dialogContext);
                                  await Future.delayed(
                                      const Duration(milliseconds: 100));
                                  if (!context.mounted) return;
                                  showMoreOptionsMenu(context, ref, message);
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

  static void showMoreOptionsMenu(
      BuildContext context, WidgetRef ref, Message message) {
    final config = ref.read(chatUiConfigProvider);
    final primary =
        config.primaryActionColor ?? config.iconColor ?? Colors.blue;
    final notifier = ref.read(threadMessagesProvider.notifier);
    final roomId = notifier.roomId;

    showModalBottomSheet<void>(
      context: context,
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
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final ok = await ref
                      .read(threadMessagesProvider.notifier)
                      .togglePinMessage(message.id, !message.pin);
                  if (!context.mounted) return;
                  showChatToast(
                    context,
                    message: ok
                        ? (message.pin ? 'Đã bỏ ghim tin nhắn' : 'Đã ghim tin nhắn')
                        : 'Không thể cập nhật ghim tin nhắn',
                    isError: !ok,
                    config: config,
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.remove_red_eye_outlined,
                  color: primary,
                ),
                title: const Text('Danh sách người xem'),
                onTap: () {
                  Navigator.of(sheetContext).pushReplacement(
                    ModalBottomSheetRoute<void>(
                      builder: (_) => MessageReadersSheet(
                        roomId: roomId,
                        messageId: message.id,
                      ),
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                    ),
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

  static Future<void> _deleteMessage(
      BuildContext context, WidgetRef ref, Message message) async {
    final confirmed = await showChatConfirmDialog(
      context: context,
      config: ref.read(chatUiConfigProvider),
      title: 'Xoá tin nhắn?',
      message:
          'Tin nhắn này sẽ bị xoá cho tất cả mọi người trong cuộc trò chuyện.',
      confirmLabel: 'Xoá',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final ok = await ref
        .read(threadMessagesProvider.notifier)
        .deleteMessage(message.id);
    if (!context.mounted) return;
    showChatToast(
      context,
      message: ok ? 'Đã xoá tin nhắn' : 'Không thể xoá tin nhắn',
      isError: !ok,
      config: ref.read(chatUiConfigProvider),
    );
  }

  static Future<void> _editMessage(
      BuildContext context, WidgetRef ref, Message message) async {
    final newContent = await showChatTextInputDialog(
      context: context,
      config: ref.read(chatUiConfigProvider),
      title: 'Sửa tin nhắn',
      hintText: 'Nội dung tin nhắn...',
      initialValue: message.content,
    );
    if (newContent == null || newContent.trim().isEmpty || !context.mounted) {
      return;
    }
    final ok = await ref
        .read(threadMessagesProvider.notifier)
        .updateMessage(message.id, newContent.trim());
    if (!context.mounted) return;
    showChatToast(
      context,
      message: ok ? 'Đã sửa tin nhắn' : 'Không thể sửa tin nhắn',
      isError: !ok,
      config: ref.read(chatUiConfigProvider),
    );
  }
}
