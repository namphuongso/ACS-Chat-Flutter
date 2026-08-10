import '../../domain/entities/conversation.dart';
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

  void dispose() => _dataSource.dispose();
}
