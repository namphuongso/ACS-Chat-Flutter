import 'package:http/http.dart' as http;

import '../../../../core/config/chat_module_config.dart';
import '../../../../core/constants/chat_api_endpoints.dart';
import '../../../../core/network/json_api_client.dart';
import '../../../auth_token/domain/repositories/chat_auth_token_provider.dart';
import 'read_status_remote_datasource.dart';

class ReadStatusRemoteDataSourceImpl implements ReadStatusRemoteDataSource {
  ReadStatusRemoteDataSourceImpl({
    required ChatModuleConfig config,
    required ChatAuthTokenProvider appTokenProvider,
    http.Client? httpClient,
  })  : _api = JsonApiClient(
          backendBaseUrl: config.backendBaseUrl,
          httpClient: httpClient,
        ),
        _appTokenProvider = appTokenProvider;

  final JsonApiClient _api;
  final ChatAuthTokenProvider _appTokenProvider;

  @override
  Future<void> markAsRead(String conversationId) async {
    final appToken = await _appTokenProvider.getAppToken();
    await _api.post(
      ChatApiEndpoints.markConversationRead(conversationId),
      appToken: appToken,
      allowEmptyBody: true,
    );
  }

  void dispose() => _api.dispose();
}
