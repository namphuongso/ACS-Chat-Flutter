import 'package:riverpod/riverpod.dart';

import 'chat_module_config.dart';
import '../auth_token/domain/chat_auth_token_provider.dart';

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
