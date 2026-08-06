import 'package:riverpod/riverpod.dart';

import '../shared/providers.dart';
import 'data/token_manager.dart';
import 'domain/auth_token_repository.dart';

final authTokenRepositoryProvider = Provider<AuthTokenRepository>((ref) {
  final config = ref.watch(chatModuleConfigProvider);
  final tokenProvider = ref.watch(chatAuthTokenProviderProvider);
  final manager = TokenManager(
    backendBaseUrl: config.backendBaseUrl,
    appTokenProvider: tokenProvider,
  );
  ref.onDispose(manager.dispose);
  return manager;
});
