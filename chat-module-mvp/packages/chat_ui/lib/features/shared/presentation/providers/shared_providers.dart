import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_cache_providers.dart';

final chatModuleConfigProvider = Provider<ChatModuleConfig>((ref) {
  throw UnimplementedError(
    'chatModuleConfigProvider chưa được override. '
    'Host app phải cung cấp ChatModuleConfig trước khi dùng module chat.',
  );
});

final chatAuthTokenProviderProvider = Provider<ChatAuthTokenProvider>((ref) {
  throw UnimplementedError(
    'chatAuthTokenProviderProvider chưa được override. '
    'Host app phải cung cấp cách lấy app JWT token.',
  );
});

final authTokenRepositoryProvider = Provider<AuthTokenRepository>((ref) {
  // Riverpod 3 dispose provider khi hết listener — nếu để vậy, cache token
  // ACS (lưu trong RAM của repo) sẽ bị xóa khi rời màn hình chat → mỗi lần
  // mở room lại gọi join-room + BE cấp token mới. keepAlive để 1 instance
  // sống suốt vòng đời app, token tái sử dụng tới khi thực sự hết hạn.
  ref.keepAlive();
  final config = ref.watch(chatModuleConfigProvider);
  final tokenProvider = ref.watch(chatAuthTokenProviderProvider);
  final dataSource = AuthTokenRemoteDataSourceImpl(
    config: config,
    appTokenProvider: tokenProvider,
  );
  final repo = AuthTokenRepositoryImpl(dataSource);
  ref.onDispose(repo.dispose);
  return repo;
});

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  final config = ref.watch(chatModuleConfigProvider);
  final tokenProvider = ref.watch(chatAuthTokenProviderProvider);
  final local = ref.watch(conversationLocalDataSourceProvider);
  final dataSource = ConversationRemoteDataSourceImpl(
    config: config,
    appTokenProvider: tokenProvider,
  );
  final repo = ConversationRepositoryImpl(dataSource, localDataSource: local);
  ref.onDispose(repo.dispose);
  return repo;
});

final readStatusRepositoryProvider = Provider<ReadStatusRepository>((ref) {
  final config = ref.watch(chatModuleConfigProvider);
  final tokenProvider = ref.watch(chatAuthTokenProviderProvider);
  final dataSource = ReadStatusRemoteDataSourceImpl(
    config: config,
    appTokenProvider: tokenProvider,
  );
  final repo = ReadStatusRepositoryImpl(dataSource);
  ref.onDispose(repo.dispose);
  return repo;
});

// Use Cases Providers
final getAccessTokenUseCaseProvider = Provider<GetAccessTokenUseCase>((ref) {
  final repo = ref.watch(authTokenRepositoryProvider);
  return GetAccessTokenUseCase(repo);
});

final getOrCreateDirectConversationUseCaseProvider =
    Provider<GetOrCreateDirectConversationUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return GetOrCreateDirectConversationUseCase(repo);
});

final listConversationsUseCaseProvider =
    Provider<ListConversationsUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return ListConversationsUseCase(repo);
});

final getConversationUseCaseProvider = Provider<GetConversationUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return GetConversationUseCase(repo);
});

final pinConversationUseCaseProvider = Provider<PinConversationUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return PinConversationUseCase(repo);
});

final markAsReadUseCaseProvider = Provider<MarkAsReadUseCase>((ref) {
  final repo = ref.watch(readStatusRepositoryProvider);
  return MarkAsReadUseCase(repo);
});
