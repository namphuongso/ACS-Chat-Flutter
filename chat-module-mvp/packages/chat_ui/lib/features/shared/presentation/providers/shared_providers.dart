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
    appTokenProvider: appTokenProvider,
  );
  final repo = MessageRepositoryImpl(
    remoteDataSource: remote,
    realtimeDataSource: realtime,
    localDataSource: local,
  );
  ref.onDispose(repo.dispose);
  return repo;
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

final createGroupConversationUseCaseProvider =
    Provider<CreateGroupConversationUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return CreateGroupConversationUseCase(repo);
});

final getMembersUseCaseProvider = Provider<GetMembersUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return GetMembersUseCase(repo);
});

final updateRoomInfoUseCaseProvider = Provider<UpdateRoomInfoUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return UpdateRoomInfoUseCase(repo);
});

final addParticipantsUseCaseProvider = Provider<AddParticipantsUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return AddParticipantsUseCase(repo);
});

final removeParticipantsUseCaseProvider =
    Provider<RemoveParticipantsUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return RemoveParticipantsUseCase(repo);
});

final transferOwnershipUseCaseProvider =
    Provider<TransferOwnershipUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return TransferOwnershipUseCase(repo);
});

final setRoleAdminUseCaseProvider = Provider<SetRoleAdminUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return SetRoleAdminUseCase(repo);
});

final leaveRoomUseCaseProvider = Provider<LeaveRoomUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return LeaveRoomUseCase(repo);
});

final closeRoomUseCaseProvider = Provider<CloseRoomUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return CloseRoomUseCase(repo);
});

final uploadRoomAvatarUseCaseProvider = Provider<UploadRoomAvatarUseCase>((ref) {
  return UploadRoomAvatarUseCase(ref.watch(conversationRepositoryProvider));
});

class GlobalCurrentUserIdNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setUserId(String userId) {
    state = userId;
  }
}

final globalCurrentUserIdProvider =
    NotifierProvider<GlobalCurrentUserIdNotifier, String>(
        GlobalCurrentUserIdNotifier.new);

final currentUserIdProvider = Provider<String>((ref) {
  return ref.watch(globalCurrentUserIdProvider);
});
