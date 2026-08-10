import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifiers/conversation_list_notifier.dart';

final conversationListProvider =
    NotifierProvider<ConversationListNotifier, List<Conversation>>(
        ConversationListNotifier.new);
