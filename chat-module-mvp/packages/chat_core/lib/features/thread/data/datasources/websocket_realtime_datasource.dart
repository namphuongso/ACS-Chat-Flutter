import '../models/message_model.dart';

/// Interface nguồn dữ liệu realtime qua kết nối WebSocket Backend.
abstract class WebSocketRealtimeDataSource {
  Stream<MessageModel> watchNewMessages(String roomId, String threadId);

  Stream<MessageModel> watchListMessages();

  Future<void> stopWatching(String threadId);

  Future<void> stopWatchingList();

  void sendReadMessage(String lastVisibleMessageId, {String? roomId});

  void clearReadMessageState();

  void leaveActiveRoom();

  void resetSession();

  Future<void> dispose();
}

/// Alias tương thích ngược cho tên cũ NativeRealtimeDataSource.
typedef NativeRealtimeDataSource = WebSocketRealtimeDataSource;
