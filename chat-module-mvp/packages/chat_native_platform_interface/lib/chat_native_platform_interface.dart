import 'package:flutter/services.dart';

/// Raw event nhận từ native — CHỈ chứa field cần thiết (theo mục 6
/// kế hoạch gốc: "chỉ gửi field cần thiết qua channel, không serialize
/// nguyên object ACS SDK").
class NativeChatMessageEvent {
  const NativeChatMessageEvent({
    required this.threadId,
    required this.messageId,
    required this.senderId,
    required this.senderDisplayName,
    required this.content,
    required this.createdAtIso8601,
  });

  final String threadId;
  final String messageId;
  final String senderId;
  final String senderDisplayName;
  final String content;
  final String createdAtIso8601;

  factory NativeChatMessageEvent.fromMap(Map<dynamic, dynamic> map) {
    return NativeChatMessageEvent(
      threadId: map['threadId'] as String,
      messageId: map['messageId'] as String,
      senderId: map['senderId'] as String,
      senderDisplayName: map['senderDisplayName'] as String,
      content: map['content'] as String,
      createdAtIso8601: map['createdAt'] as String,
    );
  }
}

/// API duy nhất module Flutter cần biết về phần native. Không expose
/// gì khác ngoài init + stream sự kiện — đúng phạm vi cố định mục 3
/// kế hoạch gốc ("Native chỉ đảm nhiệm đúng 1 việc").
class ChatNativePlatformInterface {
  ChatNativePlatformInterface({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel =
            methodChannel ?? const MethodChannel('com.npp.chatnative/methods'),
        _eventChannel =
            eventChannel ?? const EventChannel('com.npp.chatnative/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<NativeChatMessageEvent>? _cachedStream;

  /// Khởi tạo ChatClient native với token ACS hiện tại + gọi
  /// startRealtimeNotifications(). Phải gọi lại mỗi khi token refresh
  /// (native tự update credential, không tạo lại toàn bộ connection).
  Future<void> initialize({
    required String acsToken,
    required String acsUserId,
    required String endpoint,
  }) async {
    await _methodChannel.invokeMethod<void>('initialize', {
      'token': acsToken,
      'userId': acsUserId,
      'endpoint': endpoint,
    });
  }

  /// Stream broadcast — nhiều nơi trong app có thể listen cùng lúc,
  /// native chỉ mở 1 kết nối duy nhất bất kể bao nhiêu listener Dart.
  Stream<NativeChatMessageEvent> get messageEvents {
    return _cachedStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => NativeChatMessageEvent.fromMap(event as Map));
  }

  /// Gọi khi app vào background hoặc không còn thread nào cần theo dõi
  /// — đóng kết nối realtime để tiết kiệm pin/network (mục 6 kế hoạch gốc).
  Future<void> stopRealtimeNotifications() async {
    await _methodChannel.invokeMethod<void>('stopRealtimeNotifications');
  }
}
