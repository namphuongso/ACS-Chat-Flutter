import '../../../../core/domain/entities/chat_member.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/room_update_type.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../datasources/conversation_local_datasource.dart';
import '../datasources/conversation_remote_datasource.dart';

class ConversationRepositoryImpl implements ConversationRepository {
  ConversationRepositoryImpl(this._dataSource,
      {ConversationLocalDataSource? localDataSource})
      : _local = localDataSource;

  final ConversationRemoteDataSource _dataSource;
  final ConversationLocalDataSource? _local;

  @override
  Future<Conversation> getOrCreateDirectConversation(String otherUserId) async {
    final conversation =
        await _dataSource.getOrCreateDirectConversation(otherUserId);
    await _saveToCache([conversation]);
    return conversation;
  }

  @override
  Future<PaginatedResult<Conversation>> listConversations({
    String? cursor,
    int limit = 20,
  }) async {
    final pageIndex = int.tryParse(cursor ?? '') ?? 0;
    try {
      final result = await _dataSource.listConversations(
        pageIndex: pageIndex,
        limit: limit,
      );
      await _saveToCache(result.items);
      return PaginatedResult(
        items: result.items,
        hasMore: result.hasMore,
        cursor: result.nextPageIndex?.toString(),
      );
    } catch (_) {
      // Offline / lỗi mạng — trả cache thay vì ném lỗi.
      final cached = await getCachedConversations();
      if (cached.isNotEmpty) {
        return PaginatedResult(items: cached, hasMore: false);
      }
      rethrow;
    }
  }

  @override
  Future<List<Conversation>> getCachedConversations() async {
    final local = _local;
    if (local == null) return const [];
    try {
      return await local.getCachedConversations();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<Conversation> getConversation(String conversationId) async {
    final conversation = await _dataSource.getConversation(conversationId);
    await _saveToCache([conversation]);
    return conversation;
  }

  @override
  Future<bool> pinConversation(String conversationId, bool pin) async {
    final result = await _dataSource.pinRoom(conversationId, pin);
    // Cập nhật cache để UI phản ánh ngay trạng thái ghim.
    final local = _local;
    if (local != null && result) {
      try {
        final cached = await local.getCachedConversations();
        final updated = cached
            .map((c) => c.id == conversationId ? c.copyWith(pin: pin) : c)
            .toList();
        await local.saveConversations(updated);
      } catch (_) {
        // Cache lỗi không nên làm hỏng luồng chính.
      }
    }
    return result;
  }

  Future<void> _saveToCache(List<Conversation> conversations) async {
    final local = _local;
    if (local == null) return;
    try {
      final cached = await local.getCachedConversations();
      final byId = <String, Conversation>{
        for (final c in cached) c.id: c,
        for (final c in conversations) c.id: c,
      };
      await local.saveConversations(byId.values.toList());
    } catch (_) {
      // Cache lỗi không nên làm hỏng luồng chính.
    }
  }

  @override
  Future<Conversation> createGroupConversation({
    required List<String> participantIds,
    required String roomName,
    String? avatarUrl,
  }) async {
    final conversation = await _dataSource.createGroupConversation(
      participantIds: participantIds,
      roomName: roomName,
      avatarUrl: avatarUrl,
    );
    await _saveToCache([conversation]);
    return conversation;
  }

  @override
  Future<List<ChatMember>> getMembers(String roomId) async {
    return await _dataSource.getMembers(roomId);
  }

  @override
  Future<List<RoomUpdateType>> getRoomUpdateTypes() async {
    return await _dataSource.getRoomUpdateTypes();
  }

  @override
  Future<bool> updateRoomInfo({
    required String roomId,
    required String roomName,
    String? avatarUrl,
    required String roomType,
    String? updateType,
  }) async {
    final result = await _dataSource.updateRoomInfo(
      roomId: roomId,
      roomName: roomName,
      avatarUrl: avatarUrl,
      roomType: roomType,
      updateType: updateType,
    );
    final local = _local;
    if (local != null && result) {
      try {
        final cached = await local.getCachedConversations();
        final updated = cached.map((c) {
          if (c.id == roomId) {
            return c.copyWith(roomName: roomName, avatarUrl: avatarUrl);
          }
          return c;
        }).toList();
        await local.saveConversations(updated);
      } catch (_) {}
    }
    return result;
  }

  @override
  Future<int> addParticipants({
    required String roomId,
    required List<String> participantIds,
  }) async {
    final count = await _dataSource.addParticipants(
      roomId: roomId,
      participantIds: participantIds,
    );
    if (count > 0) {
      await _syncConversationMembers(roomId);
    }
    return count;
  }

  @override
  Future<int> removeParticipants({
    required String roomId,
    required List<String> participantIds,
  }) async {
    final count = await _dataSource.removeParticipants(
      roomId: roomId,
      participantIds: participantIds,
    );
    if (count > 0) {
      await _syncConversationMembers(roomId);
    }
    return count;
  }

  @override
  Future<bool> transferOwnership({
    required String roomId,
    required String toUserId,
  }) async {
    final result = await _dataSource.transferOwnership(
      roomId: roomId,
      toUserId: toUserId,
    );
    if (result) {
      await _syncConversationMembers(roomId);
    }
    return result;
  }

  @override
  Future<bool> setRoleAdmin({
    required String roomId,
    required String userId,
    required bool admin,
  }) async {
    final result = await _dataSource.setRoleAdmin(
      roomId: roomId,
      userId: userId,
      admin: admin,
    );
    if (result) {
      await _syncConversationMembers(roomId);
    }
    return result;
  }

  @override
  Future<bool> leaveRoom({
    required String roomId,
    String? newAdminUserId,
  }) async {
    final result = await _dataSource.leaveRoom(
      roomId: roomId,
      newAdminUserId: newAdminUserId,
    );
    final local = _local;
    if (local != null && result) {
      try {
        final cached = await local.getCachedConversations();
        final updated = cached.where((c) => c.id != roomId).toList();
        await local.saveConversations(updated);
      } catch (_) {}
    }
    return result;
  }

  @override
  Future<bool> closeRoom({required String roomId}) async {
    final result = await _dataSource.closeRoom(roomId: roomId);
    final local = _local;
    if (local != null && result) {
      try {
        final cached = await local.getCachedConversations();
        final updated = cached.where((c) => c.id != roomId).toList();
        await local.saveConversations(updated);
      } catch (_) {}
    }
    return result;
  }

  @override
  Future<String> uploadRoomAvatar({
    required String filePath,
    required String filename,
  }) =>
      _dataSource.uploadFileViaSas(filePath: filePath, fileName: filename);

  @override
  Future<String> uploadFileViaSas({
    required String filePath,
    required String fileName,
    String? contentType,
    String? documentId,
    void Function(int sent, int total)? onProgress,
  }) =>
      _dataSource.uploadFileViaSas(
        filePath: filePath,
        fileName: fileName,
        contentType: contentType,
        documentId: documentId,
        onProgress: onProgress,
      );

  Future<void> _syncConversationMembers(String roomId) async {
    final local = _local;
    if (local == null) return;
    try {
      final members = await getMembers(roomId);
      final cached = await local.getCachedConversations();
      final updated = cached.map((c) {
        if (c.id == roomId) {
          return c.copyWith(participants: members);
        }
        return c;
      }).toList();
      await local.saveConversations(updated);
    } catch (_) {}
  }

  void dispose() => _dataSource.dispose();
}
