import '../../../../core/constants/chat_api_endpoints.dart';
import '../../../../core/data/models/chat_user_model.dart';
import '../../../../core/network/json_api_client.dart';
import '../../../auth_token/domain/repositories/chat_auth_token_provider.dart';
import '../../../conversation_list/domain/entities/conversation.dart';
import '../../../../core/domain/entities/chat_user.dart';
import 'contact_remote_datasource.dart';

class ContactRemoteDataSourceImpl implements ContactRemoteDataSource {
  ContactRemoteDataSourceImpl({
    required JsonApiClient api,
    required ChatAuthTokenProvider appTokenProvider,
  })  : _api = api,
        _appTokenProvider = appTokenProvider;

  final ChatAuthTokenProvider _appTokenProvider;
  final JsonApiClient _api;

  @override
  Future<PaginatedResult<ChatUser>> searchContacts({
    String? keyword,
    int pageIndex = 0,
    int pageSize = 15,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();

    final query = <String, String>{
      'pageIndex': pageIndex.toString(),
      'pageSize': pageSize.toString(),
      // Backend get-contacts là endpoint dạng "search": luôn cần có param
      // `keyword` (kể cả rỗng = trả tất cả). Trước đây bỏ qua keyword rỗng
      // khiến request "list all" thiếu param → BE trả 401 (UNAUTHORIZED),
      // trong khi request có keyword (khi tìm kiếm) lại thành công.
      'keyword': keyword ?? '',
    };

    final data = await _api.get(
      ChatApiEndpoints.getContacts,
      query: query,
      appToken: appToken,
    );

    final items = (data as List? ?? [])
        .map((e) => ChatUserModel.fromJson(e as Map<String, dynamic>))
        .toList();

    return PaginatedResult(
      items: items,
      hasMore: items.length >= pageSize,
    );
  }
}
