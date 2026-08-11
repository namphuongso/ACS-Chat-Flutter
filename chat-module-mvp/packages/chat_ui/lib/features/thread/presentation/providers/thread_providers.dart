import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/providers/local_cache_providers.dart';
import '../../../shared/presentation/providers/shared_providers.dart';
import '../notifiers/thread_messages_notifier.dart';

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  final config = ref.watch(chatModuleConfigProvider);
  final authTokenRepo = ref.watch(authTokenRepositoryProvider);
  final appTokenProvider = ref.watch(chatAuthTokenProviderProvider);
  final local = ref.watch(messageLocalDataSourceProvider);

  final remote = MessageRemoteDataSourceImpl(
    config: config,
    authTokenRepository: authTokenRepo,
    appTokenProvider: appTokenProvider,
  );
  final realtime = NativeRealtimeDataSourceImpl(
    config: config,
    authTokenRepository: authTokenRepo,
  );
  final repo = MessageRepositoryImpl(
    remoteDataSource: remote,
    realtimeDataSource: realtime,
    localDataSource: local,
  );
  ref.onDispose(repo.dispose);
  return repo;
});

// Thread Use Cases
final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return SendMessageUseCase(repo);
});

final updateMessageUseCaseProvider = Provider<UpdateMessageUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return UpdateMessageUseCase(repo);
});

final deleteMessageUseCaseProvider = Provider<DeleteMessageUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return DeleteMessageUseCase(repo);
});

final listMessagesUseCaseProvider = Provider<ListMessagesUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return ListMessagesUseCase(repo);
});

final watchNewMessagesUseCaseProvider =
    Provider<WatchNewMessagesUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return WatchNewMessagesUseCase(repo);
});

final stopWatchingMessagesUseCaseProvider =
    Provider<StopWatchingMessagesUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return StopWatchingMessagesUseCase(repo);
});

final watchListMessagesUseCaseProvider =
    Provider<WatchListMessagesUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return WatchListMessagesUseCase(repo);
});

final stopWatchingListMessagesUseCaseProvider =
    Provider<StopWatchingListMessagesUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return StopWatchingListMessagesUseCase(repo);
});

final pinMessageUseCaseProvider = Provider<PinMessageUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return PinMessageUseCase(repo);
});

final getPinnedMessagesUseCaseProvider =
    Provider<GetPinnedMessagesUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return GetPinnedMessagesUseCase(repo);
});

final roomIdProvider = Provider<String>((ref) => throw UnimplementedError());
final threadIdProvider = Provider<String>((ref) => throw UnimplementedError());
final currentUserIdProvider =
    Provider<String>((ref) => throw UnimplementedError());

final threadMessagesProvider =
    NotifierProvider.autoDispose<ThreadMessagesNotifier, List<Message>>(
  ThreadMessagesNotifier.new,
  dependencies: [
    roomIdProvider,
    threadIdProvider,
    listMessagesUseCaseProvider,
    watchNewMessagesUseCaseProvider,
    sendMessageUseCaseProvider,
    updateMessageUseCaseProvider,
    deleteMessageUseCaseProvider,
    pinMessageUseCaseProvider,
    stopWatchingMessagesUseCaseProvider,
    getPinnedMessagesUseCaseProvider,
  ],
);
