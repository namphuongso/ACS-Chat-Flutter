import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifiers/conversation_list_notifier.dart';

/// Trạng thái đang load lần đầu của danh sách room — dùng cho skeleton
/// loading (tránh nhầm với "chưa có cuộc trò chuyện nào" khi danh sách rỗng).
export '../notifiers/conversation_list_notifier.dart'
    show conversationListLoadingProvider;

final conversationListProvider =
    NotifierProvider<ConversationListNotifier, List<Conversation>>(
        ConversationListNotifier.new);
