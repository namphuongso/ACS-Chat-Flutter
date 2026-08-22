import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

class _MockRemote implements MessageRemoteDataSource {
  PaginatedResult<MessageModel>? listResult;
  bool throwOnList = false;
  int listCalls = 0;

  @override
  Future<PaginatedResult<MessageModel>> listMessages({
    required String roomId,
    required String threadId,
    String? startTime,
    String? cursor,
  }) async {
    listCalls++;
    if (throwOnList) throw Exception('network down');
    return listResult ??
        PaginatedResult<MessageModel>(items: [], hasMore: false);
  }

  @override
  Future<MessageModel> sendMessage({
    required String roomId,
    required String threadId,
    required String content,
    Map<String, dynamic>? metaData,
  }) async {
    return MessageModel(
      id: 'sent-$content',
      threadId: threadId,
      senderId: 'me',
      senderDisplayName: '',
      content: content,
      type: MessageType.text,
      createdAt: DateTime(2026, 2, 1),
      status: MessageDeliveryStatus.sent,
      metadata: metaData,
    );
  }

  @override
  Future<bool> updateMessage({
    required String roomId,
    required String messageId,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    return true;
  }

  @override
  Future<bool> deleteMessage({
    required String roomId,
    required String messageId,
  }) async {
    return true;
  }

  @override
  Future<bool> pinMessage(String messageId, bool pin) async => true;

  @override
  Future<List<PinnedMessageModel>> getPinnedMessages(String roomId) async =>
      const [];

  @override
  Future<List<MessageReaderModel>> getMessageReaders({
    required String roomId,
    required String messageId,
    bool? read,
  }) async =>
      const [];

  @override
  Future<List<ReactionConfig>> getReactionConfigs() async => const [];

  @override
  Future<List<MessageReaction>> getMessageReactions({
    required String roomId,
    required String messageId,
  }) async =>
      const [];

  @override
  Future<List<MessageReactionSummary>> getRoomReactions(String roomId) async =>
      const [];

  @override
  Future<PaginatedResult<MessageResourceModel>> getMessageResources({
    required String roomId,
    required MessageResourceType resourceType,
    int pageIndex = 1,
    int pageSize = 50,
    String? keyword,
  }) async =>
      const PaginatedResult<MessageResourceModel>(items: [], hasMore: false);

  @override
  Future<bool> reactMessage({
    required String roomId,
    required String threadId,
    required String messageId,
    required String reactionCode,
  }) async =>
      true;

  @override
  Stream<MessageModel> watchNewMessages(String roomId, String threadId) =>
      const Stream.empty();

  @override
  Future<void> stopWatching(String threadId) async {}

  @override
  Future<void> dispose() async {}
}

class _MockRealtime implements NativeRealtimeDataSource {
  @override
  Stream<MessageModel> watchNewMessages(String roomId, String threadId) =>
      const Stream.empty();

  @override
  Stream<MessageModel> watchListMessages() =>
      const Stream.empty();

  @override
  Future<void> stopWatching(String threadId) async {}

  @override
  Future<void> stopWatchingList() async {}

  @override
  void sendReadMessage(String lastVisibleMessageId, {String? roomId}) {}

  @override
  void clearReadMessageState() {}

  @override
  void leaveActiveRoom() {}

  @override
  void resetSession() {}

  @override
  Future<void> dispose() async {}
}

class _MemoryLocal implements MessageLocalDataSource {
  final Map<String, List<Message>> _store = {};

  @override
  Future<List<Message>> getCachedMessages(String threadId) async =>
      List.unmodifiable(_store[threadId] ?? const []);

  @override
  Future<void> saveMessages(String threadId, List<Message> messages) async {
    _store[threadId] = messages;
  }

  @override
  Future<void> clear(String threadId) async {
    _store.remove(threadId);
  }
}

Message _message(String id, {DateTime? createdAt}) => Message(
      id: id,
      threadId: 't1',
      senderId: 'u1',
      senderDisplayName: 'A',
      content: 'hi',
      type: MessageType.text,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
    );

void main() {
  group('MessageRepositoryImpl local cache', () {
    test('listMessages lưu kết quả vào cache sau khi remote thành công',
        () async {
      final remote = _MockRemote()
        ..listResult = PaginatedResult<MessageModel>(
          items: [
            MessageModel.fromAcsJson({
              'id': 'm1',
              'content': {'message': 'hello'},
              'type': 'text',
              'createdOn': '2026-01-01T00:00:00Z',
            }, threadId: 't1'),
          ],
          hasMore: false,
        );
      final local = _MemoryLocal();
      final repo = MessageRepositoryImpl(
        remoteDataSource: remote,
        realtimeDataSource: _MockRealtime(),
        localDataSource: local,
      );

      await repo.listMessages(roomId: 'r1', threadId: 't1');

      expect(await local.getCachedMessages('t1'), hasLength(1));
      expect(remote.listCalls, 1);
    });

    test('listMessages trả cache khi remote lỗi (offline)', () async {
      final remote = _MockRemote()..throwOnList = true;
      final local = _MemoryLocal();
      await local.saveMessages('t1', [_message('cached1')]);
      final repo = MessageRepositoryImpl(
        remoteDataSource: remote,
        realtimeDataSource: _MockRealtime(),
        localDataSource: local,
      );

      final result = await repo.listMessages(roomId: 'r1', threadId: 't1');

      expect(result.items.map((m) => m.id), ['cached1']);
      expect(result.hasMore, isFalse);
    });

    test('getCachedMessages trả về dữ liệu đã lưu', () async {
      final local = _MemoryLocal();
      await local.saveMessages('t1', [_message('m1')]);
      final repo = MessageRepositoryImpl(
        remoteDataSource: _MockRemote(),
        realtimeDataSource: _MockRealtime(),
        localDataSource: local,
      );

      final cached = await repo.getCachedMessages('t1');
      expect(cached.map((m) => m.id), ['m1']);
    });

    test('sendMessage ghi tin vào cache', () async {
      final remote = _MockRemote();
      final local = _MemoryLocal();
      final repo = MessageRepositoryImpl(
        remoteDataSource: remote,
        realtimeDataSource: _MockRealtime(),
        localDataSource: local,
      );

      final sent = await repo.sendMessage(
        roomId: 'r1',
        threadId: 't1',
        content: 'hello',
      );

      expect(sent.id, 'sent-hello');
      expect((await local.getCachedMessages('t1')).map((m) => m.id), [
        'sent-hello',
      ]);
    });

    test('sendMessage tin mới nằm ĐẦU cache (cache theo thứ tự mới-nhất trước)',
        () async {
      final remote = _MockRemote();
      final local = _MemoryLocal();
      final repo = MessageRepositoryImpl(
        remoteDataSource: remote,
        realtimeDataSource: _MockRealtime(),
        localDataSource: local,
      );
      await local.saveMessages('t1', [_message('old')]);

      await repo.sendMessage(
        roomId: 'r1',
        threadId: 't1',
        content: 'hello',
      );

      // Tin mới phải đứng trước tin cũ — trước đây append vào cuối làm cache
      // đảo thứ tự, lần vào sau đọc cache render tin bị ngược rồi mới sửa.
      expect((await local.getCachedMessages('t1')).map((m) => m.id), [
        'sent-hello',
        'old',
      ]);
    });
  });
}
