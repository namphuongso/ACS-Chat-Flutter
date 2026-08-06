import 'package:riverpod/riverpod.dart';

import '../shared/providers.dart';
import 'data/rest_read_status_repository.dart';
import 'domain/read_status_repository.dart';

final readStatusRepositoryProvider = Provider<ReadStatusRepository>((ref) {
  final config = ref.watch(chatModuleConfigProvider);
  final tokenProvider = ref.watch(chatAuthTokenProviderProvider);
  return RestReadStatusRepository(
    config: config,
    appTokenProvider: tokenProvider,
  );
});
