import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

class _MockConversationRemote implements ConversationRemoteDataSource {
  @override
  Future<bool> closeRoom({required String roomId}) async => true;

  @override
  Future<bool> setRoleAdmin({
    required String roomId,
    required String userId,
    required bool admin,
  }) async =>
      true;

  @override
  Future<String> uploadRoomAvatar({
    required String filePath,
    required String filename,
  }) async =>
      'https://example.com/avatar.png';

  @override
  Future<String> uploadFileViaSas({
    required String filePath,
    required String fileName,
    String? contentType,
    String? documentId,
    void Function(int sent, int total)? onProgress,
  }) async =>
      'https://example.com/file.png';

  @override
  Future<ConversationModel> createGroupConversation({
    required List<String> participantIds,
    required String roomName,
    String? avatarUrl,
  }) async {
    return ConversationModel(
      id: 'group-123',
      threadId: 'thread-group-123',
      type: ConversationType.group,
      participants: participantIds
          .map((id) => ChatUser(id: id, displayName: 'User $id'))
          .toList(),
      createdAt: DateTime(2026, 8, 11),
      updatedAt: DateTime(2026, 8, 11),
      roomName: roomName,
      avatarUrl: avatarUrl,
    );
  }

  @override
  Future<List<ChatMemberModel>> getMembers(String roomId) async {
    return [
      const ChatMemberModel(
        id: 'user-1',
        displayName: 'User One',
        isAdmin: true,
      ),
      const ChatMemberModel(
        id: 'user-2',
        displayName: 'User Two',
        isAdmin: false,
      ),
    ];
  }

  @override
  Future<List<RoomUpdateType>> getRoomUpdateTypes() async {
    return const [
      RoomUpdateType(
        id: '1',
        code: 'Name',
        name: 'Cập nhật tên phòng',
      ),
      RoomUpdateType(
        id: '2',
        code: 'Avatar',
        name: 'Cập nhật ảnh đại diện',
      ),
    ];
  }

  @override
  Future<bool> updateRoomInfo({
    required String roomId,
    required String roomName,
    String? avatarUrl,
    required String roomType,
    String? updateType,
  }) async {
    return true;
  }

  @override
  Future<int> addParticipants({
    required String roomId,
    required List<String> participantIds,
  }) async {
    return participantIds.length;
  }

  @override
  Future<int> removeParticipants({
    required String roomId,
    required List<String> participantIds,
  }) async {
    return participantIds.length;
  }

  @override
  Future<bool> transferOwnership({
    required String roomId,
    required String toUserId,
  }) async {
    return true;
  }

  @override
  Future<bool> leaveRoom({
    required String roomId,
    String? newAdminUserId,
  }) async {
    return true;
  }

  @override
  Future<ConversationModel> getOrCreateDirectConversation(
      String otherUserId) async {
    throw UnimplementedError();
  }

  @override
  Future<ConversationModel> getConversation(String conversationId) async {
    throw UnimplementedError();
  }

  @override
  Future<PaginatedConversations> listConversations({
    required int pageIndex,
    int limit = 20,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> pinRoom(String roomId, bool pin) async {
    return true;
  }

  @override
  void dispose() {}
}

class _MemoryConversationLocal implements ConversationLocalDataSource {
  List<Conversation> _store = [];

  @override
  Future<List<Conversation>> getCachedConversations() async {
    return List.unmodifiable(_store);
  }

  @override
  Future<void> saveConversations(List<Conversation> conversations) async {
    _store = List.from(conversations);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}

void main() {
  group('Group Conversation Tests', () {
    late _MockConversationRemote remote;
    late _MemoryConversationLocal local;
    late ConversationRepositoryImpl repository;

    setUp(() {
      remote = _MockConversationRemote();
      local = _MemoryConversationLocal();
      repository = ConversationRepositoryImpl(remote, localDataSource: local);
    });

    test(
        'createGroupConversation saves group to cache and returns correct data',
        () async {
      final conversation = await repository.createGroupConversation(
        participantIds: ['user-1', 'user-2'],
        roomName: 'Test Group',
        avatarUrl: 'https://avatar.url',
      );

      expect(conversation.id, 'group-123');
      expect(conversation.roomName, 'Test Group');
      expect(conversation.avatarUrl, 'https://avatar.url');
      expect(conversation.type, ConversationType.group);
      expect(conversation.participants.length, 2);

      final cached = await local.getCachedConversations();
      expect(cached.length, 1);
      expect(cached.first.id, 'group-123');
    });

    test('getMembers returns correct members list', () async {
      final members = await repository.getMembers('group-123');

      expect(members.length, 2);
      expect(members[0].id, 'user-1');
      expect(members[0].isAdmin, isTrue);
      expect(members[1].id, 'user-2');
      expect(members[1].isAdmin, isFalse);
    });

    test('updateRoomInfo updates local cache', () async {
      // Setup initial cache
      final initial = Conversation(
        id: 'group-123',
        threadId: 'thread-group-123',
        type: ConversationType.group,
        participants: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        roomName: 'Old Name',
      );
      await local.saveConversations([initial]);

      final success = await repository.updateRoomInfo(
        roomId: 'group-123',
        roomName: 'New Name',
        avatarUrl: 'https://new.avatar.url',
        roomType: 'G',
      );

      expect(success, isTrue);

      final cached = await local.getCachedConversations();
      expect(cached.length, 1);
      expect(cached.first.roomName, 'New Name');
      expect(cached.first.avatarUrl, 'https://new.avatar.url');
    });

    test('addParticipants and removeParticipants sync members to local cache',
        () async {
      // Setup initial cache
      final initial = Conversation(
        id: 'group-123',
        threadId: 'thread-group-123',
        type: ConversationType.group,
        participants: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        roomName: 'Test Group',
      );
      await local.saveConversations([initial]);

      final added = await repository.addParticipants(
        roomId: 'group-123',
        participantIds: ['user-3'],
      );
      expect(added, 1);

      // Verify cache contains members fetched from remote (getMembers returns user-1, user-2)
      var cached = await local.getCachedConversations();
      expect(cached.first.participants.length, 2);
      expect(cached.first.participants[0].id, 'user-1');

      final removed = await repository.removeParticipants(
        roomId: 'group-123',
        participantIds: ['user-2'],
      );
      expect(removed, 1);

      cached = await local.getCachedConversations();
      expect(cached.first.participants.length, 2);
    });

    test('transferOwnership syncs members to local cache', () async {
      final initial = Conversation(
        id: 'group-123',
        threadId: 'thread-group-123',
        type: ConversationType.group,
        participants: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        roomName: 'Test Group',
      );
      await local.saveConversations([initial]);

      final success = await repository.transferOwnership(
        roomId: 'group-123',
        toUserId: 'user-2',
      );
      expect(success, isTrue);

      final cached = await local.getCachedConversations();
      expect(cached.first.participants.length, 2);
    });
  });
}
