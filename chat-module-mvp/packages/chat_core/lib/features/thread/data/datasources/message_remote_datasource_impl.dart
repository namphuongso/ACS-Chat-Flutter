import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../auth_token/domain/repositories/auth_token_repository.dart';
import '../../../auth_token/domain/repositories/chat_auth_token_provider.dart';
import '../../../conversation_list/domain/entities/conversation.dart';
import '../../../../core/config/chat_module_config.dart';
import '../../../../core/constants/chat_api_endpoints.dart';
import '../../../../core/error/chat_api_exception.dart';
import '../../../../core/utils/chat_logger.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/message_reaction.dart';
import '../models/message_model.dart';
import '../models/pinned_message_model.dart';
import '../models/message_reader_model.dart';
import '../models/message_resource_model.dart';
import '../../domain/entities/message_resource.dart';
import 'message_remote_datasource.dart';
import 'polling_engine.dart';

class MessageRemoteDataSourceImpl implements MessageRemoteDataSource {
  MessageRemoteDataSourceImpl({
    required ChatModuleConfig config,
    required AuthTokenRepository authTokenRepository,
    required ChatAuthTokenProvider appTokenProvider,
    http.Client? httpClient,
  })  : _config = config,
        _authTokenRepository = authTokenRepository,
        _appTokenProvider = appTokenProvider,
        _http = httpClient ?? http.Client();

  final ChatModuleConfig _config;
  final AuthTokenRepository _authTokenRepository;
  final ChatAuthTokenProvider _appTokenProvider;
  final http.Client _http;

  final Map<String, PollingEngine<MessageModel>> _activePolling = {};

  @override
  Future<MessageModel> sendMessage({
    required String roomId,
    required String threadId,
    required String content,
    Map<String, dynamic>? metaData,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final token = await _authTokenRepository.getAccessToken(roomId);
    final uri =
        Uri.parse('${_config.backendBaseUrl}${ChatApiEndpoints.sendMessage}');
    final payloadMetadata = metaData ?? <String, dynamic>{};
    final requestContent = content.trim().isEmpty ? '[Hình ảnh]' : content.trim();
    final requestBody = jsonEncode({
      'roomId': roomId,
      'content': requestContent,
      'metaData': payloadMetadata,
    });

    final requestHeaders = _headers(appToken);
    ChatLogger.logRequest('POST', uri, headers: requestHeaders, body: {'roomId': roomId, 'content': requestContent, 'metaData': payloadMetadata});

    final response = await _http
        .post(
          uri,
          headers: _headers(appToken),
          body: requestBody,
        )
        .timeout(const Duration(seconds: 15));

    ChatLogger.logResponse('POST', uri, response.statusCode, response.body);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'ACS_SEND_FAILED',
        message: response.body,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final messageId = json['data'] as String? ??
        'msg-${DateTime.now().millisecondsSinceEpoch}';

    return MessageModel(
      id: messageId,
      threadId: threadId,
      senderId: token.acsUserId,
      senderDisplayName: '',
      content: content,
      type: MessageType.text,
      createdAt: DateTime.now(),
      status: MessageDeliveryStatus.sent,
      metadata: metaData,
    );
  }

  @override
  Future<PaginatedResult<MessageModel>> listMessages({
    required String roomId,
    required String threadId,
    String? startTime,
    String? cursor,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final uri = Uri.parse(
      '${_config.backendBaseUrl}${ChatApiEndpoints.getMessages}',
    ).replace(queryParameters: {
      'roomId': roomId,
      'pageSize': '50',
      if (cursor != null && cursor.isNotEmpty) 'continuationToken': cursor,
    });

    ChatLogger.logRequest('GET (messages)', uri);

    final response = await _http.get(
      uri,
      headers: {'Authorization': 'Bearer $appToken'},
    ).timeout(const Duration(seconds: 15));

    ChatLogger.logResponse(
        'GET (messages)', uri, response.statusCode, response.body);

    if (response.statusCode != 200) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'GET_MESSAGES_FAILED',
        message: response.body,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    final rawItems = (data['items'] as List? ?? data['messages'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    Map<String, dynamic>? nextPayload;
    for (var i = rawItems.length - 1; i >= 0; i--) {
      final item = rawItems[i];
      final itemType = item['itemType']?.toString();
      final itemData = (itemType != null && item['data'] is Map)
          ? Map<String, dynamic>.from(item['data'] as Map)
          : item;
      final eventType = itemData['eventType']?.toString();

      if (eventType == 'RoomUpdated') {
        final payload = (itemData['payload'] is Map)
            ? Map<String, dynamic>.from(itemData['payload'] as Map)
            : <String, dynamic>{};
        final roomName = (payload['roomName'] ?? itemData['roomName'] ?? '').toString().trim();
        final avatarUrl = (payload['avatarUrl'] ?? itemData['avatarUrl'] ?? '').toString().trim();

        if (nextPayload != null) {
          final nextRoomName = (nextPayload['roomName'] ?? '').toString().trim();
          final nextAvatarUrl = (nextPayload['avatarUrl'] ?? '').toString().trim();
          final nameChanged = roomName.isNotEmpty && nextRoomName.isNotEmpty && roomName != nextRoomName;
          final avatarChanged = avatarUrl != nextAvatarUrl && (avatarUrl.isNotEmpty || nextAvatarUrl.isNotEmpty);

          if (nameChanged) payload['isNameChanged'] = true;
          if (avatarChanged) payload['isAvatarChanged'] = true;
        } else {
          if (roomName.isNotEmpty && avatarUrl.isEmpty) {
            payload['isNameChanged'] = true;
          } else if (avatarUrl.isNotEmpty && roomName.isEmpty) {
            payload['isAvatarChanged'] = true;
          }
        }

        nextPayload = payload;
        itemData['payload'] = payload;
        if (itemType != null && item['data'] is Map) {
          item['data'] = itemData;
        } else {
          item.addAll(itemData);
        }
      }
    }

    final rawMessages = rawItems
        .map((e) => MessageModel.fromAcsJson(e, threadId: threadId))
        .toList();
    final continuationToken = data['continuationToken']?.toString();
    final hasMore = data['hasMore'] == true &&
        continuationToken != null &&
        continuationToken.isNotEmpty;

    return PaginatedResult(
      items: rawMessages,
      hasMore: hasMore,
      cursor: hasMore ? continuationToken : null,
    );
  }

  @override
  Future<bool> updateMessage({
    required String roomId,
    required String messageId,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final uri =
        Uri.parse('${_config.backendBaseUrl}${ChatApiEndpoints.updateMessage}');
    final requestBody = jsonEncode({
      'roomId': roomId,
      'messageId': messageId,
      'content': content,
      'metaData': metadata ?? {},
    });

    ChatLogger.logRequest('POST (update message)', uri, body: {'roomId': roomId, 'messageId': messageId, 'content': content});

    final response = await _http
        .post(
          uri,
          headers: _headers(appToken),
          body: requestBody,
        )
        .timeout(const Duration(seconds: 15));

    ChatLogger.logResponse('POST (update message)', uri, response.statusCode, response.body);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'ACS_UPDATE_FAILED',
        message: response.body,
      );
    }
    return true;
  }

  @override
  Future<bool> deleteMessage({
    required String roomId,
    required String messageId,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final uri =
        Uri.parse('${_config.backendBaseUrl}${ChatApiEndpoints.deleteMessage}');
    final requestBody = jsonEncode({
      'roomId': roomId,
      'messageId': messageId,
    });

    ChatLogger.logRequest('POST (delete message)', uri, body: {'roomId': roomId, 'messageId': messageId});

    final response = await _http
        .post(
          uri,
          headers: _headers(appToken),
          body: requestBody,
        )
        .timeout(const Duration(seconds: 15));

    ChatLogger.logResponse('POST (delete message)', uri, response.statusCode, response.body);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'ACS_DELETE_FAILED',
        message: response.body,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['data'] == true;
  }

  @override
  Future<bool> pinMessage(String messageId, bool pin) async {
    final appToken = await _appTokenProvider.getAppToken();
    final uri =
        Uri.parse('${_config.backendBaseUrl}${ChatApiEndpoints.pinMessage}')
            .replace(queryParameters: {'messageId': messageId, 'pin': '$pin'});

    ChatLogger.logRequest('POST (pin message)', uri);

    final response = await _http.post(
      uri,
      headers: _headers(appToken),
    ).timeout(const Duration(seconds: 15));

    ChatLogger.logResponse('POST (pin message)', uri, response.statusCode, response.body);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'PIN_MESSAGE_FAILED',
        message: response.body,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['data'] == true;
  }

  @override
  Future<List<PinnedMessageModel>> getPinnedMessages(String roomId) async {
    final appToken = await _appTokenProvider.getAppToken();
    final uri = Uri.parse(
        '${_config.backendBaseUrl}${ChatApiEndpoints.getPinnedMessages(roomId)}');

    ChatLogger.logRequest('GET (pinned messages)', uri);

    final response = await _http.get(
      uri,
      headers: _headers(appToken),
    ).timeout(const Duration(seconds: 15));

    ChatLogger.logResponse('GET (pinned messages)', uri, response.statusCode, response.body);

    if (response.statusCode != 200) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'GET_PINNED_FAILED',
        message: response.body,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(PinnedMessageModel.fromJson)
        .toList();
  }

  @override
  Future<List<MessageReaderModel>> getMessageReaders({
    required String roomId,
    required String messageId,
    bool? read,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final queryParams = <String, String>{
      'roomId': roomId,
      'messageId': messageId,
    };
    if (read != null) {
      queryParams['read'] = '$read';
    }

    final uri = Uri.parse(
      '${_config.backendBaseUrl}${ChatApiEndpoints.getReader}',
    ).replace(queryParameters: queryParams);

    ChatLogger.logRequest('GET (get-reader)', uri);

    final response = await _http
        .get(uri, headers: _headers(appToken))
        .timeout(const Duration(seconds: 15));

    ChatLogger.logResponse(
      'GET (get-reader)',
      uri,
      response.statusCode,
      response.body,
    );

    if (response.statusCode != 200) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'GET_READER_FAILED',
        message: response.body,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(MessageReaderModel.fromJson)
        .toList();
  }

  @override
  Future<PaginatedResult<MessageResourceModel>> getMessageResources({
    required String roomId,
    required MessageResourceType resourceType,
    int pageIndex = 1,
    int pageSize = 50,
    String? keyword,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final queryParams = <String, String>{
      'roomId': roomId,
      'resourceType': resourceType.value,
      'pageIndex': '$pageIndex',
      'pageSize': '$pageSize',
    };
    if (keyword != null && keyword.trim().isNotEmpty) {
      queryParams['keyword'] = keyword.trim();
    }

    final uri = Uri.parse(
      '${_config.backendBaseUrl}${ChatApiEndpoints.getMessageResources}',
    ).replace(queryParameters: queryParams);

    ChatLogger.logRequest('GET (get-message-resources)', uri);

    final response = await _http
        .get(uri, headers: _headers(appToken))
        .timeout(const Duration(seconds: 15));

    ChatLogger.logResponse(
      'GET (get-message-resources)',
      uri,
      response.statusCode,
      response.body,
    );

    if (response.statusCode != 200) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'GET_RESOURCES_FAILED',
        message: response.body,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'];
    final totalRecord = (json['totalRecord'] as num?)?.toInt() ?? 0;
    if (data is! List) {
      return const PaginatedResult<MessageResourceModel>(
        items: [],
        hasMore: false,
      );
    }

    final items = data
        .whereType<Map<String, dynamic>>()
        .map((item) => MessageResourceModel.fromJson(item, resourceType))
        .toList();

    final hasMore = (pageIndex * pageSize) < totalRecord;

    return PaginatedResult<MessageResourceModel>(
      items: items,
      hasMore: hasMore,
      cursor: hasMore ? '${pageIndex + 1}' : null,
      totalCount: totalRecord,
    );
  }

  @override
  Future<List<ReactionConfig>> getReactionConfigs() async {
    final appToken = await _appTokenProvider.getAppToken();
    final uri = Uri.parse(
      '${_config.backendBaseUrl}${ChatApiEndpoints.getReactionConfigs}',
    ).replace(queryParameters: {'pageIndex': '1', 'pageSize': '50'});
    final response = await _http.get(
      uri,
      headers: _headers(appToken),
    ).timeout(const Duration(seconds: 15));
    ChatLogger.logResponse(
        'GET (reaction configs)', uri, response.statusCode, response.body);
    if (response.statusCode != 200) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'GET_REACTION_CONFIGS_FAILED',
        message: response.body,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((item) => ReactionConfig(
              id: item['id']?.toString() ?? item['reactionId']?.toString(),
              code: item['reactionCode']?.toString() ?? item['code']?.toString() ?? '',
              displayName: item['displayName']?.toString() ?? '',
              iconUrl: item['iconUrl']?.toString() ?? '',
            ))
        .where((item) => item.code.isNotEmpty)
        .toList();
  }

  @override
  Future<List<MessageReaction>> getMessageReactions({
    required String roomId,
    required String messageId,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final uri = Uri.parse(
      '${_config.backendBaseUrl}${ChatApiEndpoints.getMessageReactions}',
    ).replace(queryParameters: {
      'roomId': roomId,
      'messageId': messageId,
      'pageIndex': '1',
      'pageSize': '50',
    });
    final response = await _http.get(
      uri,
      headers: _headers(appToken),
    ).timeout(const Duration(seconds: 15));
    ChatLogger.logResponse(
        'GET (message reactions)', uri, response.statusCode, response.body);
    if (response.statusCode != 200) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'GET_MESSAGE_REACTIONS_FAILED',
        message: response.body,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((item) => MessageReaction(
              userId: item['userId']?.toString() ?? '',
              contactName: item['contactName']?.toString() ?? '',
              avatarUrl: item['avatarUrl']?.toString(),
              reactionCode: item['reactionCode']?.toString() ?? '',
              reactionIconUrl: item['reactionIconUrl']?.toString() ?? '',
              reactedAt: DateTime.tryParse(
                item['reactedDate']?.toString() ?? '',
              )?.toLocal(),
            ))
        .toList();
  }

  @override
  Future<List<MessageReactionSummary>> getRoomReactions(String roomId) async {
    final appToken = await _appTokenProvider.getAppToken();
    final uri = Uri.parse(
      '${_config.backendBaseUrl}${ChatApiEndpoints.getRoomReactions(roomId)}',
    ).replace(queryParameters: {'pageIndex': '1', 'pageSize': '50'});
    final response = await _http.get(
      uri,
      headers: _headers(appToken),
    ).timeout(const Duration(seconds: 15));
    ChatLogger.logResponse(
        'GET (room reactions)', uri, response.statusCode, response.body);
    if (response.statusCode != 200) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'GET_ROOM_REACTIONS_FAILED',
        message: response.body,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((item) => MessageReactionSummary(
              messageId: item['messageId']?.toString() ?? '',
              totalReactions: int.tryParse(
                    item['totalReactions']?.toString() ?? '',
                  ) ??
                  0,
              myReactionCode: item['myReactionCode']?.toString(),
              myReactionIconUrl: item['myReactionIconUrl']?.toString(),
              previewIconUrl: _reactionPreviewIcon(item),
            ))
        .where((item) => item.messageId.isNotEmpty)
        .toList();
  }

  String? _extractIcon(Map<dynamic, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _reactionPreviewIcon(Map<String, dynamic> item) {
    final mine = _extractIcon(item, const [
      'myReactionIconUrl',
      'myReactionIcon',
      'reactionIconUrl',
      'reactionIcon',
      'iconUrl',
      'IconUrl',
    ]);
    if (mine != null && mine.isNotEmpty) return mine;

    final others = item['otherReaction'] ?? item['otherReactions'] ?? item['others'];
    if (others is List) {
      for (final raw in others.whereType<Map>()) {
        final map = raw.cast<dynamic, dynamic>();
        final icon = _extractIcon(map, const [
          'reactionIconUrl',
          'reactionIcon',
          'iconUrl',
          'IconUrl',
          'myReactionIconUrl',
          'myReactionIcon',
        ]);
        if (icon != null && icon.isNotEmpty) return icon;
      }
    }
    return null;
  }

  @override
  Future<bool> reactMessage({
    required String roomId,
    required String threadId,
    required String messageId,
    required String reactionCode,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final uri = Uri.parse(
      '${_config.backendBaseUrl}${ChatApiEndpoints.reactionMessage}',
    );
    final payload = <String, dynamic>{
      'messageId': messageId,
      'roomId': roomId,
      'threadId': threadId,
    };
    if (reactionCode.isNotEmpty && reactionCode != '0') {
      payload['reactionId'] = reactionCode;
      payload['reactionCode'] = reactionCode;
    }
    final headers = _headers(appToken);
    final body = jsonEncode(payload);
    ChatLogger.logRequest('POST (reaction message)', uri, headers: headers, body: body);

    final response = await _http.post(
      uri,
      headers: headers,
      body: body,
    ).timeout(const Duration(seconds: 15));
    ChatLogger.logResponse(
        'POST (reaction message)', uri, response.statusCode, response.body);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'REACTION_MESSAGE_FAILED',
        message: response.body,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['data'] == true;
  }

  @override
  Stream<MessageModel> watchNewMessages(String roomId, String threadId) {
    final existing = _activePolling[threadId];
    if (existing != null) return existing.stream;

    final engine = PollingEngine<MessageModel>(
      threadId: threadId,
      baseInterval: _config.pollingIntervalSmallGroup,
      fetchNewMessages: ({startTime}) async {
        final result = await listMessages(
            roomId: roomId, threadId: threadId, startTime: startTime);
        return result.items;
      },
    );
    _activePolling[threadId] = engine;
    engine.start();
    return engine.stream;
  }

  @override
  Future<void> stopWatching(String threadId) async {
    final engine = _activePolling.remove(threadId);
    await engine?.dispose();
  }

  @override
  Future<void> dispose() async {
    for (final engine in _activePolling.values) {
      await engine.dispose();
    }
    _activePolling.clear();
    _http.close();
  }

  Map<String, String> _headers(String appToken) => {
        'Authorization': 'Bearer $appToken',
        'Content-Type': 'application/json',
        if (_config.apiKey != null && _config.apiKey!.isNotEmpty)
          'X-API-KEY': _config.apiKey!,
      };
}
