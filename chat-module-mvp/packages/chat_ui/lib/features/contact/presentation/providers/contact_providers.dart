import 'package:chat_core/chat_core.dart';
import 'package:chat_core/chat_core_impl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/providers/shared_providers.dart';

final contactRemoteDataSourceProvider =
    Provider<ContactRemoteDataSource>((ref) {
  final config = ref.watch(chatModuleConfigProvider);
  return ContactRemoteDataSourceImpl(
    api: JsonApiClient(backendBaseUrl: config.backendBaseUrl),
    appTokenProvider: ref.watch(chatAuthTokenProviderProvider),
  );
});

final contactRepositoryProvider = Provider<ContactRepository>((ref) {
  return ContactRepositoryImpl(ref.watch(contactRemoteDataSourceProvider));
});

final searchContactsUseCaseProvider = Provider<SearchContactsUseCase>((ref) {
  return SearchContactsUseCase(ref.watch(contactRepositoryProvider));
});
