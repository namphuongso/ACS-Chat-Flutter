import 'dart:async';

import '../../../conversation_list/domain/entities/conversation.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/pinned_message.dart';
import '../../domain/repositories/message_repository.dart';
import '../datasources/message_local_datasource.dart';
import '../datasources/message_remote_datasource.dart';
import '../datasources/native_realtime_datasource.dart';

/// Repository tổng hợp: send/list qua REST (BE + ACS), realtime ưu tiên
/// native (EventChannel), polling của [MessageRemoteDataSource] là nguồn
/// dự phòng khi native không sẵn sàng.
///
/// Local cache: cache-first khi đọc lịch sử (hiện nhanh, offline vẫn đọc
/// được). Mọi tin gửi/realtime/list cũng được ghi lại vào cache.
class MessageRepositoryImpl implements MessageRepository {
  MessageRepositoryImpl({
    required MessageRemoteDataSource remoteDataSource,
    required NativeRealtimeDataSource realtimeDataSource,
    MessageLocalDataSource? localDataSource,
  })  : _remote = remoteDataSource,
        _realtime = realtimeDataSource,
        _local = localDataSource;

  final MessageRemoteDataSource _remote;
  final NativeRealtimeDataSource _realtime;
  final MessageLocalDataSource? _local;

  @override
  Future<Message> sendMessage({
    required String roomId,
    required String threadId,
    required String content,
  }) async {
    final message = await _remote.sendMessage(
        roomId: roomId, threadId: threadId, content: content);
    await _appendToCache(threadId, message);
    return message;
  }

  @override
  Future<PaginatedResult<Message>> listMessages({
    required String roomId,
    required String threadId,
    String? startTime,
    String? cursor,
  }) async {
    try {
      final result = await _remote.listMessages(
        roomId: roomId,
        threadId: threadId,
        startTime: startTime,
        cursor: cursor,
      );
      // Trả kết quả ĐÃ merge pin từ cache — nếu không, tin ghim sẽ bị
      // mất UI khi load lại lịch sử (remote không mang field pin).
      final merged = await _saveToCache(threadId, result.items);
      return PaginatedResult(
        items: merged,
        hasMore: result.hasMore,
        cursor: result.cursor,
      );
    } catch (_) {
      // Offline / lỗi mạng — trả cache đã lưu thay vì ném lỗi. Không có
      // cache thì ném tiếp để UI biết (không có dữ liệu nào để hiện).
      final cached = await getCachedMessages(threadId);
      if (cached.isNotEmpty) {
        return PaginatedResult(items: cached, hasMore: false);
      }
      rethrow;
    }
  }

  @override
  Future<List<Message>> getCachedMessages(String threadId) async {
    final local = _local;
    if (local == null) return const [];
    try {
      return await local.getCachedMessages(threadId);
    } catch (_) {
      return const [];
    }
  }

  /// Lưu tin vào cache và TRẢ VỀ danh sách theo đúng thứ tự remote,
  /// nhưng gắn lại cờ pin từ cache (remote không trả field pin).
  Future<List<Message>> _saveToCache(
      String threadId, List<Message> messages) async {
    final local = _local;
    if (local == null) return messages;
    try {
      final cached = await local.getCachedMessages(threadId);
      final pinnedIds = <String>{
        for (final m in cached)
          if (m.pin) m.id,
      };
      await local.saveMessages(threadId, _mergeById(cached, messages));
      return [
        for (final m in messages)
          if (pinnedIds.contains(m.id)) m.copyWith(pin: true) else m,
      ];
    } catch (_) {
      // Cache lỗi không nên làm hỏng luồng chính.
      return messages;
    }
  }

  Future<void> _appendToCache(String threadId, Message message) async {
    final local = _local;
    if (local == null) return;
    try {
      final cached = await local.getCachedMessages(threadId);
      await local.saveMessages(threadId, _mergeById(cached, [message]));
    } catch (_) {
      // Cache lỗi không nên làm hỏng luồng chính.
    }
  }

  List<Message> _mergeById(List<Message> existing, List<Message> incoming) {
    final byId = <String, Message>{
      for (final m in existing) m.id: m,
    };
    for (final m in incoming) {
      final old = byId[m.id];
      if (old != null && old.pin) {
        byId[m.id] = m.copyWith(pin: true);
      } else {
        byId[m.id] = m;
      }
    }
    return byId.values.toList();
  }

  @override
  Future<bool> pinMessage({
    required String threadId,
    required String messageId,
    required bool pin,
  }) async {
    final success = await _remote.pinMessage(messageId, pin);
    final local = _local;
    if (success && local != null) {
      try {
        final cached = await local.getCachedMessages(threadId);
        final updated = cached
            .map((m) => m.id == messageId ? m.copyWith(pin: pin) : m)
            .toList();
        await local.saveMessages(threadId, updated);
      } catch (_) {}
    }
    return success;
  }

  @override
  Future<List<PinnedMessage>> getPinnedMessages(String roomId) =>
      _remote.getPinnedMessages(roomId);

  @override
  Stream<Message> watchNewMessages(String roomId, String threadId) {
    // Có thể switch qua _remoteDataSource nếu quyết định dùng Polling
    // return _remote.watchNewMessages(roomId, threadId);
    final stream = _realtime.watchNewMessages(roomId, threadId);
    if (_local == null) return stream;
    return stream.map((message) {
      unawaited(_appendToCache(threadId, message));
      return message;
    });
  }

  @override
  Future<void> stopWatching(String threadId) =>
      _realtime.stopWatching(threadId);

  @override
  Stream<Message> watchListMessages(String roomId) {
    final stream = _realtime.watchListMessages(roomId);
    if (_local == null) return stream;
    return stream.map((message) {
      unawaited(_appendToCache(message.threadId, message));
      return message;
    });
  }

  @override
  Future<void> stopWatchingList() => _realtime.stopWatchingList();

  Future<void> dispose() async {
    await _realtime.dispose();
    await _remote.dispose();
  }
}
