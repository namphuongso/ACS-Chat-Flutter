import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../../auth_token/domain/repositories/auth_token_repository.dart';
import '../../../auth_token/domain/repositories/chat_auth_token_provider.dart';
import '../../../conversation_list/domain/entities/conversation.dart';
import '../../../../core/config/chat_module_config.dart';
import '../../../../core/constants/chat_api_endpoints.dart';
import '../../../../core/error/chat_api_exception.dart';
import '../../domain/entities/message.dart';
import '../models/message_model.dart';
import '../models/pinned_message_model.dart';
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

  // TODO(verify-acs-api-version): xác nhận lại api-version mới nhất của
  // ACS Chat REST API trước khi dùng thật — chưa gọi thử được trong
  // sandbox này. Xem Microsoft Learn "Chat API reference".
  static const _acsApiVersion = '2024-03-07';

  @override
  Future<MessageModel> sendMessage({
    required String roomId,
    required String threadId,
    required String content,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final token = await _authTokenRepository.getAccessToken(roomId);
    final uri =
        Uri.parse('${_config.backendBaseUrl}${ChatApiEndpoints.sendMessage}');
    final requestBody = jsonEncode({
      'roomId': roomId,
      'content': content,
      'metaData': {},
    });

    developer.log('POST Request: $uri\nBody: $requestBody', name: 'ChatModule');

    final response = await _http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $appToken',
            'Content-Type': 'application/json',
          },
          body: requestBody,
        )
        .timeout(const Duration(seconds: 15));

    developer.log('POST Response [${response.statusCode}]: ${response.body}',
        name: 'ChatModule');

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
    );
  }

  @override
  Future<PaginatedResult<MessageModel>> listMessages({
    required String roomId,
    required String threadId,
    String? startTime,
    String? cursor,
  }) async {
    final token = await _authTokenRepository.getAccessToken(roomId);

    final Uri uri;
    if (cursor != null && cursor.isNotEmpty) {
      if (cursor.startsWith('http')) {
        uri = Uri.parse(cursor);
      } else {
        final query = {
          'api-version': _acsApiVersion,
          'skip': cursor,
        };
        uri = Uri.parse(
                '${_config.acsEndpoint}${ChatApiEndpoints.acsThreadMessages(threadId)}')
            .replace(queryParameters: query);
      }
    } else {
      final query = {
        'api-version': _acsApiVersion,
        'maxpagesize': '20',
        if (startTime != null) 'startTime': startTime,
      };
      uri = Uri.parse(
              '${_config.acsEndpoint}${ChatApiEndpoints.acsThreadMessages(threadId)}')
          .replace(queryParameters: query);
    }

    developer.log('GET Request (ACS): $uri', name: 'ChatModule');

    final response = await _http.get(
      uri,
      headers: {'Authorization': 'Bearer ${token.token}'},
    ).timeout(const Duration(seconds: 15));

    developer.log(
        'GET Response (ACS) [${response.statusCode}]: ${response.body}',
        name: 'ChatModule');

    if (response.statusCode != 200) {
      throw ChatApiException(
        statusCode: response.statusCode,
        code: 'ACS_LIST_FAILED',
        message: response.body,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rawMessages = (json['value'] as List? ?? [])
        .where((e) =>
            (e as Map<String, dynamic>)['type'] == 'text' ||
            e['type'] == 'html')
        .map((e) => MessageModel.fromAcsJson(e as Map<String, dynamic>,
            threadId: threadId))
        .toList();

    return PaginatedResult(
      items: rawMessages,
      hasMore: json['nextLink'] != null,
      cursor: json['nextLink'] as String?,
    );
  }

  @override
  Future<bool> pinMessage(String messageId, bool pin) async {
    final appToken = await _appTokenProvider.getAppToken();
    final uri =
        Uri.parse('${_config.backendBaseUrl}${ChatApiEndpoints.pinMessage}')
            .replace(queryParameters: {'messageId': messageId, 'pin': '$pin'});

    developer.log('POST Request (pin message): $uri', name: 'ChatModule');

    final response = await _http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $appToken',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));

    developer.log(
        'POST Response (pin message) [${response.statusCode}]: '
        '${response.body}',
        name: 'ChatModule');

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

    developer.log('GET Request (pinned messages): $uri', name: 'ChatModule');

    final response = await _http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $appToken',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));

    developer.log(
        'GET Response (pinned messages) [${response.statusCode}]: '
        '${response.body}',
        name: 'ChatModule');

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
}
