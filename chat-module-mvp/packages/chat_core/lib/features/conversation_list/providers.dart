import 'package:riverpod/riverpod.dart';

import '../shared/providers.dart';
import 'data/rest_conversation_repository.dart';
import 'domain/conversation.dart';
import 'domain/conversation_repository.dart';

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  final config = ref.watch(chatModuleConfigProvider);
  final tokenProvider = ref.watch(chatAuthTokenProviderProvider);
  return RestConversationRepository(
    config: config,
    appTokenProvider: tokenProvider,
  );
});

final conversationListProvider =
    StateNotifierProvider<ConversationListNotifier, List<Conversation>>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return ConversationListNotifier(repo);
});

class ConversationListNotifier extends StateNotifier<List<Conversation>> {
  ConversationListNotifier(this.repo) : super([]) {
    refresh();
  }

  final ConversationRepository repo;
  String? _cursor;

  Future<void> refresh() async {
    final result = await repo.listConversations();
    state = result.items;
    _cursor = result.cursor;
  }

  Future<void> loadMore() async {
    if (_cursor == null) return;
    final result = await repo.listConversations(cursor: _cursor);
    state = [...state, ...result.items];
    _cursor = result.cursor;
  }
}
