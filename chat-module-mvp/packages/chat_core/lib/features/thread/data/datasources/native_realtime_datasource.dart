import '../models/message_model.dart';

/// Nguồn dữ liệu realtime qua native (EventChannel) — chỉ đảm nhiệm
/// watch/stop, mọi việc khác do [MessageRemoteDataSource] lo.
abstract class NativeRealtimeDataSource {
  Stream<MessageModel> watchNewMessages(String roomId, String threadId);

  /// Nhận tin mới cho TOÀN BỘ hội thoại của user (không cần mở thread) —
  /// realtime native là client-level (`startRealtimeNotifications()`), sự
  /// kiện của mọi thread đều đến. [roomId] chỉ dùng để lấy ACS token.
  Stream<MessageModel> watchListMessages(String roomId);

  Future<void> stopWatching(String threadId);

  Future<void> stopWatchingList();

  void sendReadMessage(String lastVisibleMessageId);

  void clearReadMessageState();

  void leaveActiveRoom();

  void resetSession();

  Future<void> dispose();
}
