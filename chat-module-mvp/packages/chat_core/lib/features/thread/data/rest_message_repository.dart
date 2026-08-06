import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../auth_token/domain/auth_token_repository.dart';
import '../../conversation_list/domain/conversation.dart';
import '../../shared/chat_api_exception.dart';
import '../../shared/chat_module_config.dart';
import '../domain/message.dart';
import '../domain/message_repository.dart';
import 'polling_engine.dart';

class RestMessageRepository implements MessageRepository {
  RestMessageRepository({
    required ChatModuleConfig config,
    required AuthTokenRepository authTokenRepository,
    http.Client? httpClient,
  })  : _config = config,
        _authTokenRepository = authTokenRepository,
        _http = httpClient ?? http.Client();

  final ChatModuleConfig _config;
  final AuthTokenRepository _authTokenRepository;
  final http.Client _http;

  final Map<String, PollingEngine> _activePolling = {};

  // TODO(verify-acs-api-version): xác nhận lại api-version mới nhất của
  // ACS Chat REST API trước khi dùng thật — chưa gọi thử được trong
  // sandbox này. Xem Microsoft Learn "Chat API reference".
  static const _acsApiVersion = '2024-03-07';

  @override
  Future<Message> sendMessage({
    required String threadId,
    required String content,
  }) async {
    final token = await _authTokenRepository.getAccessToken();
    final response = await _http.post(
      Uri.parse('${token.endpoint}/chat/threads/$threadId/messages'
          '?api-version=$_acsApiVersion'),
      headers: {
        'Authorization': 'Bearer ${token.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'content': content,
        'senderDisplayName': token.user.displayName,
      }),
    );

    if (response.statusCode != 201) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'ACS_SEND_FAILED',
        message: response.body,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return Message(
      id: json['id'] as String,
      threadId: threadId,
      senderId: token.user.acsUserId ?? token.user.id,
      senderDisplayName: token.user.displayName,
      content: content,
      type: MessageType.text,
      createdAt: DateTime.now(),
      status: MessageDeliveryStatus.sent,
    );
  }

  @override
  Future<PaginatedResult<Message>> listMessages({
    required String threadId,
    String? startTime,
    String? cursor,
  }) async {
    final token = await _authTokenRepository.getAccessToken();
    final query = {
      'api-version': _acsApiVersion,
      if (startTime != null) 'startTime': startTime,
      if (cursor != null) 'skip': cursor,
    };
    final uri = Uri.parse('${token.endpoint}/chat/threads/$threadId/messages')
        .replace(queryParameters: query);

    final response = await _http.get(
      uri,
      headers: {'Authorization': 'Bearer ${token.token}'},
    );

    if (response.statusCode != 200) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'ACS_LIST_FAILED',
        message: response.body,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rawMessages = (json['value'] as List? ?? [])
        .where((e) => (e as Map<String, dynamic>)['type'] == 'text' ||
            e['type'] == 'html')
        .map((e) => Message.fromAcsJson(e as Map<String, dynamic>, threadId: threadId))
        .toList();

    return PaginatedResult(
      items: rawMessages,
      hasMore: json['nextLink'] != null,
      cursor: json['nextLink'] as String?,
    );
  }

  @override
  Stream<Message> watchNewMessages(String threadId) {
    final existing = _activePolling[threadId];
    if (existing != null) return existing.stream;

    final engine = PollingEngine(
      threadId: threadId,
      baseInterval: _config.pollingIntervalSmallGroup,
      fetchNewMessages: ({startTime}) async {
        final result = await listMessages(threadId: threadId, startTime: startTime);
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

  Future<void> dispose() async {
    for (final engine in _activePolling.values) {
      await engine.dispose();
    }
    _activePolling.clear();
    _http.close();
  }
}
