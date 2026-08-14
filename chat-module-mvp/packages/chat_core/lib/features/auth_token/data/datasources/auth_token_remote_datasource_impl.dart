import 'package:http/http.dart' as http;

import '../../../../core/config/chat_module_config.dart';
import '../../../../core/constants/chat_api_endpoints.dart';
import '../../../../core/network/json_api_client.dart';
import '../../domain/repositories/chat_auth_token_provider.dart';
import '../models/chat_access_token_model.dart';
import 'auth_token_remote_datasource.dart';

class AuthTokenRemoteDataSourceImpl implements AuthTokenRemoteDataSource {
  AuthTokenRemoteDataSourceImpl({
    required ChatModuleConfig config,
    required ChatAuthTokenProvider appTokenProvider,
    http.Client? httpClient,
  })  : _api = JsonApiClient(
          backendBaseUrl: config.backendBaseUrl,
          apiKey: config.apiKey,
          httpClient: httpClient,
        ),
        _appTokenProvider = appTokenProvider;

  final JsonApiClient _api;
  final ChatAuthTokenProvider _appTokenProvider;

  @override
  Future<ChatAccessTokenModel> fetchToken(String roomId) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data =
        await _api.post(ChatApiEndpoints.joinRoom(roomId), appToken: appToken);
    return ChatAccessTokenModel.fromJson(data as Map<String, dynamic>);
  }

  void dispose() => _api.dispose();
}
