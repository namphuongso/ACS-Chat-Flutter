import 'package:http/http.dart' as http;

import '../../../../core/config/chat_module_config.dart';
import '../../../../core/constants/chat_api_endpoints.dart';
import '../../../../core/error/chat_api_exception.dart';
import '../../../../core/network/json_api_client.dart';
import '../../../auth_token/domain/repositories/chat_auth_token_provider.dart';
import '../models/conversation_model.dart';
import 'conversation_remote_datasource.dart';

class ConversationRemoteDataSourceImpl implements ConversationRemoteDataSource {
  ConversationRemoteDataSourceImpl({
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
  Future<ConversationModel> getOrCreateDirectConversation(
      String otherUserId) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.post(
      ChatApiEndpoints.createRoom,
      appToken: appToken,
      body: {
        'participantIds': [otherUserId],
        'roomType': 'U',
      },
    );
    if (data == null) {
      throw ChatApiException(
        statusCode: 200,
        code: 'CREATE_ROOM_NULL_DATA',
        message:
            'Không thể tạo phòng chat. Người dùng này có thể chưa được kích hoạt chat hoặc đồng bộ ACS.',
      );
    }
    return ConversationModel.fromRoomJson(data as Map<String, dynamic>);
  }

  @override
  Future<PaginatedConversations> listConversations({
    required int pageIndex,
    int limit = 20,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.get(
      ChatApiEndpoints.getRoomChats,
      appToken: appToken,
      query: {'pageIndex': '$pageIndex'},
    );

    final items = (data as List? ?? [])
        .map((e) => ConversationModel.fromJson(e as Map<String, dynamic>))
        .toList();

    // The API does not return pagination metadata, we infer hasMore from length
    final hasMore = items.isNotEmpty;

    return (
      items: items,
      hasMore: hasMore,
      nextPageIndex: hasMore ? pageIndex + 1 : null,
    );
  }

  @override
  Future<ConversationModel> getConversation(String conversationId) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.post(
      ChatApiEndpoints.joinRoom(conversationId),
      appToken: appToken,
    );
    return ConversationModel.fromRoomJson(data as Map<String, dynamic>);
  }

  @override
  Future<bool> pinRoom(String roomId, bool pin) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.post(
      ChatApiEndpoints.pinRoom,
      appToken: appToken,
      query: {'roomId': roomId, 'pin': '$pin'},
    );
    return data == true;
  }

  void dispose() => _api.dispose();
}
