import 'package:riverpod/riverpod.dart';

import '../auth_token/providers.dart';
import '../shared/providers.dart';
import 'data/native_message_repository.dart';
import 'data/rest_message_repository.dart';
import 'domain/message.dart';
import 'domain/message_repository.dart';

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  final config = ref.watch(chatModuleConfigProvider);
  final authTokenRepo = ref.watch(authTokenRepositoryProvider);

  final restRepo = RestMessageRepository(
    config: config,
    authTokenRepository: authTokenRepo,
  );
  final repo = NativeMessageRepository(
    restRepository: restRepo,
    authTokenRepository: authTokenRepo,
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final threadMessagesProvider = StateNotifierProvider.family<
    ThreadMessagesNotifier, List<Message>, String>((ref, threadId) {
  final repo = ref.watch(messageRepositoryProvider);
  final notifier = ThreadMessagesNotifier(repo: repo, threadId: threadId);
  ref.onDispose(() => repo.stopWatching(threadId));
  return notifier;
});

class ThreadMessagesNotifier extends StateNotifier<List<Message>> {
  ThreadMessagesNotifier({required this.repo, required this.threadId}) : super([]) {
    _loadHistory();
    _subscribeRealtime();
  }

  final MessageRepository repo;
  final String threadId;

  Future<void> _loadHistory() async {
    final result = await repo.listMessages(threadId: threadId);
    state = result.items.reversed.toList();
  }

  void _subscribeRealtime() {
    repo.watchNewMessages(threadId).listen((message) {
      if (state.any((m) => m.id == message.id)) return;
      state = [...state, message];
    });
  }

  Future<void> sendMessage(String content) async {
    final optimisticId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Message(
      id: optimisticId,
      threadId: threadId,
      senderId: '',
      senderDisplayName: '',
      content: content,
      type: MessageType.text,
      createdAt: DateTime.now(),
      status: MessageDeliveryStatus.sending,
    );
    state = [...state, optimistic];

    try {
      final sent = await repo.sendMessage(threadId: threadId, content: content);
      state = state.map((m) => m.id == optimisticId ? sent : m).toList();
    } catch (_) {
      state = state
          .map((m) => m.id == optimisticId
              ? m.copyWith(status: MessageDeliveryStatus.failed)
              : m)
          .toList();
    }
  }
}
