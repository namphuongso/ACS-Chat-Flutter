import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../core/config/chat_module_config.dart';
import '../../../../core/constants/chat_api_endpoints.dart';
import '../../../../core/data/models/chat_member_model.dart';
import '../../../../core/error/chat_api_exception.dart';
import '../../../../core/network/json_api_client.dart';
import '../../../../core/utils/chat_logger.dart';
import '../../../auth_token/domain/repositories/chat_auth_token_provider.dart';
import '../../domain/entities/room_update_type.dart';
import '../models/conversation_model.dart';
import 'conversation_remote_datasource.dart';

class ConversationRemoteDataSourceImpl implements ConversationRemoteDataSource {
  ConversationRemoteDataSourceImpl({
    required ChatModuleConfig config,
    required ChatAuthTokenProvider appTokenProvider,
    http.Client? httpClient,
  })  : _api = JsonApiClient(
          backendBaseUrl: config.backendBaseUrl,
          apiKey: config.apiKey,
          httpClient: httpClient,
        ),
        _appTokenProvider = appTokenProvider,
        _config = config;

  final JsonApiClient _api;
  final ChatAuthTokenProvider _appTokenProvider;
  final ChatModuleConfig _config;

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
    return data == true || (data is Map && data.isNotEmpty);
  }

  @override
  Future<ConversationModel> createGroupConversation({
    required List<String> participantIds,
    required String roomName,
    String? avatarUrl,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.post(
      ChatApiEndpoints.createRoom,
      appToken: appToken,
      body: {
        'participantIds': participantIds,
        'roomName': roomName,
        'roomType': 'G',
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      },
    );
    if (data == null) {
      throw ChatApiException(
        statusCode: 200,
        code: 'CREATE_ROOM_NULL_DATA',
        message: 'Không thể tạo phòng chat nhóm.',
      );
    }
    return ConversationModel.fromRoomJson(data as Map<String, dynamic>);
  }

  @override
  Future<List<ChatMemberModel>> getMembers(String roomId) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.get(
      ChatApiEndpoints.getMembers(roomId),
      appToken: appToken,
    );
    final rawMembers = data is List
        ? data
        : data is Map
            ? (data['members'] as List? ?? const [])
            : const [];
    return rawMembers
        .whereType<Map>()
        .map((e) => ChatMemberModel.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<RoomUpdateType>> getRoomUpdateTypes() async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.get(
      ChatApiEndpoints.getRoomUpdateTypes,
      appToken: appToken,
    );
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(RoomUpdateType.fromJson)
          .toList();
    }
    return const [];
  }

  @override
  Future<bool> updateRoomInfo({
    required String roomId,
    required String roomName,
    String? avatarUrl,
    required String roomType,
    String? updateType,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.put(
      ChatApiEndpoints.updateRoomInfo,
      appToken: appToken,
      body: {
        'roomId': roomId,
        'roomName': roomName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        'roomType': roomType,
        if (updateType != null && updateType.isNotEmpty)
          'updateType': updateType,
      },
    );
    return data == true || (data is Map && data.isNotEmpty);
  }

  @override
  Future<int> addParticipants({
    required String roomId,
    required List<String> participantIds,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.post(
      ChatApiEndpoints.addParticipants,
      appToken: appToken,
      body: {
        'roomId': roomId,
        'participants': participantIds,
      },
    );
    if (data is Map<String, dynamic>) {
      return data['addedCount'] as int? ?? 0;
    }
    return 0;
  }

  @override
  Future<int> removeParticipants({
    required String roomId,
    required List<String> participantIds,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.post(
      ChatApiEndpoints.removeParticipants,
      appToken: appToken,
      body: {
        'roomId': roomId,
        'participants': participantIds,
      },
    );
    if (data is Map<String, dynamic>) {
      return data['removedCount'] as int? ?? 0;
    }
    return 0;
  }

  @override
  Future<bool> transferOwnership({
    required String roomId,
    required String toUserId,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.post(
      ChatApiEndpoints.transferOwnership,
      appToken: appToken,
      query: {
        'roomId': roomId,
        'toUserId': toUserId,
      },
    );
    return data == true || (data is Map && data.isNotEmpty);
  }

  @override
  Future<bool> setRoleAdmin({
    required String roomId,
    required String userId,
    required bool admin,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.post(
      ChatApiEndpoints.setRoleAdmin,
      appToken: appToken,
      query: {
        'roomId': roomId,
        'userId': userId,
        'admin': admin.toString(),
      },
    );
    return data == true || (data is Map && data.isNotEmpty);
  }

  @override
  Future<bool> leaveRoom({
    required String roomId,
    String? newAdminUserId,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.post(
      ChatApiEndpoints.leaveRoom(roomId),
      appToken: appToken,
      query: {
        if (newAdminUserId != null && newAdminUserId.isNotEmpty)
          'newAdminUserId': newAdminUserId,
      },
    );
    return data == true || (data is Map && data.isNotEmpty);
  }

  @override
  Future<bool> closeRoom({required String roomId}) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.post(
      ChatApiEndpoints.closeRoom(roomId),
      appToken: appToken,
    );
    return data == true || (data is Map && data.isNotEmpty);
  }

  @override
  Future<String> uploadRoomAvatar({
    required String filePath,
    required String filename,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final data = await _api.uploadFiles(
      ChatApiEndpoints.uploadFiles,
      appToken: appToken,
      files: [(path: filePath, filename: filename)],
    );
    final urls = _extractUrls(data);
    if (urls.isEmpty) {
      throw ChatApiException(
        statusCode: 200,
        code: 'UPLOAD_EMPTY_URL',
        message: 'Upload thành công nhưng không nhận được URL file. data=$data',
      );
    }
    return urls.first;
  }

  @override
  Future<String> uploadFileViaSas({
    required String filePath,
    required String fileName,
    String? contentType,
    String? documentId,
    void Function(int sent, int total)? onProgress,
  }) async {
    final appToken = await _appTokenProvider.getAppToken();
    final file = File(filePath);
    final fileSize = await file.length();
    final mimeType = contentType ?? _lookupMimeType(fileName);

    final jsonHeaders = {
      'Authorization': 'Bearer $appToken',
      'Content-Type': 'application/json',
      if (_config.apiKey != null && _config.apiKey!.isNotEmpty)
        'X-API-KEY': _config.apiKey!,
    };

    // 1. POST /api/files/create-upload-session
    final sessionUri = Uri.parse(
      '${_api.backendBaseUrl}${ChatApiEndpoints.createUploadSession}',
    );
    final sessionRes = await http.post(
      sessionUri,
      headers: jsonHeaders,
      body: jsonEncode({
        'fileName': fileName,
        'contentType': mimeType,
        'fileSize': fileSize,
        if (documentId != null) 'documentId': documentId,
      }),
    ).timeout(const Duration(seconds: 20));
    ChatLogger.logResponse(
      'POST (create-upload-session)',
      sessionUri,
      sessionRes.statusCode,
      sessionRes.body,
    );

    if (sessionRes.statusCode != 200 && sessionRes.statusCode != 201) {
      throw ChatApiException(
        statusCode: sessionRes.statusCode,
        code: 'CREATE_UPLOAD_SESSION_FAILED',
        message: sessionRes.body,
      );
    }

    final sessionJson = jsonDecode(sessionRes.body) as Map<String, dynamic>;
    final sessionData = (sessionJson['data'] is Map)
        ? (sessionJson['data'] as Map).cast<String, dynamic>()
        : sessionJson;

    final uploadId = sessionData['uploadId']?.toString() ??
        sessionData['id']?.toString() ??
        documentId ??
        '';
    final sasUrl = sessionData['sasUrl']?.toString() ??
        sessionData['uploadUrl']?.toString() ??
        '';
    final blobName = sessionData['blobName']?.toString() ??
        sessionData['fileName']?.toString() ??
        fileName;

    if (sasUrl.isEmpty) {
      throw ChatApiException(
        statusCode: 200,
        code: 'SAS_URL_MISSING',
        message:
            'Không nhận được SAS URL từ session. Response=${sessionRes.body}',
      );
    }

    // 2. PUT file bytes to Azure Blob sasUrl with progress tracking.
    // Stream file từ đĩa thay vì đọc cả file vào RAM (tránh OOM với file
    // lớn). Timeout giãn theo dung lượng file — trước đó timeout cứng 60s
    // khiến file lớn upload trên mạng chậm bị fail giữa chừng.
    final putUri = Uri.parse(sasUrl);
    final totalBytes = fileSize;
    onProgress?.call(0, totalBytes);

    final putRequest = http.StreamedRequest('PUT', putUri);
    putRequest.headers.addAll({
      'x-ms-blob-type': 'BlockBlob',
      'Content-Type': mimeType,
      'Content-Length': '$totalBytes',
    });

    // ~512KB/s + 60s baseline, tối đa 10 phút.
    final putTimeoutSeconds =
        (60 + totalBytes ~/ (512 * 1024)).clamp(60, 600);
    final responseFuture =
        putRequest.send().timeout(Duration(seconds: putTimeoutSeconds));

    int bytesSent = 0;
    await for (final chunk in file.openRead()) {
      putRequest.sink.add(chunk);
      bytesSent += chunk.length;
      onProgress?.call(bytesSent, totalBytes);
    }
    await putRequest.sink.close();

    final streamedResponse = await responseFuture;
    final putRes = await http.Response.fromStream(streamedResponse);
    ChatLogger.logResponse(
      'PUT (Azure Blob SAS)',
      putUri,
      putRes.statusCode,
      putRes.body,
    );

    if (putRes.statusCode != 200 && putRes.statusCode != 201) {
      throw ChatApiException(
        statusCode: putRes.statusCode,
        code: 'AZURE_BLOB_PUT_FAILED',
        message: 'Lỗi PUT file lên Azure Blob SAS URL: ${putRes.body}',
      );
    }

    // 3. POST /api/files/complete-upload
    final completeUri = Uri.parse(
      '${_api.backendBaseUrl}${ChatApiEndpoints.completeUpload}',
    );
    final completeRes = await http.post(
      completeUri,
      headers: jsonHeaders,
      body: jsonEncode({
        'uploadId': uploadId,
        'blobName': blobName,
      }),
    ).timeout(const Duration(seconds: 20));
    ChatLogger.logResponse(
      'POST (complete-upload)',
      completeUri,
      completeRes.statusCode,
      completeRes.body,
    );

    if (completeRes.statusCode != 200 && completeRes.statusCode != 201) {
      throw ChatApiException(
        statusCode: completeRes.statusCode,
        code: 'COMPLETE_UPLOAD_FAILED',
        message: completeRes.body,
      );
    }

    final completeJson = jsonDecode(completeRes.body) as Map<String, dynamic>;
    final completeData = completeJson['data'];
    final blobUrl = sessionData['blobUrl']?.toString() ??
        sessionData['fileUrl']?.toString();
    final rawUrl = (blobUrl != null && blobUrl.isNotEmpty)
        ? blobUrl
        : (_extractUrls(completeData).firstOrNull ??
            _extractUrls(sessionData).firstOrNull);

    if (rawUrl == null || rawUrl.isEmpty) {
      throw ChatApiException(
        statusCode: 200,
        code: 'FINAL_FILE_URL_MISSING',
        message: 'Upload thành công nhưng không lấy được link file cuối cùng.',
      );
    }

    final finalUrl = rawUrl.split('?').first;
    return finalUrl;
  }

  String _lookupMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  List<String> _extractUrls(dynamic value) {
    final urls = <String>[];

    void visit(dynamic node) {
      if (node is String) {
        final candidate = node.trim();
        final uri = Uri.tryParse(candidate);
        if (uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            uri.host.isNotEmpty) {
          urls.add(candidate);
        }
        return;
      }
      if (node is List) {
        for (final item in node) {
          visit(item);
        }
        return;
      }
      if (node is Map) {
        // Ưu tiên các field URL phổ biến trước để URL file đứng trước các
        // link metadata khác nếu backend thay đổi envelope.
        for (final key in const [
          'url',
          'fileUrl',
          'fileURL',
          'downloadUrl',
          'path',
          'data',
          'urls',
          'files',
        ]) {
          if (node.containsKey(key)) visit(node[key]);
        }
        for (final entry in node.entries) {
          if (!const {
            'url',
            'fileUrl',
            'fileURL',
            'downloadUrl',
            'path',
            'data',
            'urls',
            'files',
          }.contains(entry.key)) {
            visit(entry.value);
          }
        }
      }
    }

    visit(value);
    return urls.toSet().toList();
  }

  void dispose() => _api.dispose();
}
