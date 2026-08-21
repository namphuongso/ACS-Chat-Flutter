import 'package:flutter/material.dart';

typedef ThreadScreenBuilder = Widget Function(
  BuildContext context, {
  required String roomId,
  required String threadId,
  required String currentUserId,
  String? title,
  String? senderAvatarUrl,
});

/// Chứa dữ liệu Deep Link đã được trích xuất từ Push Notification / URI.
class ChatDeepLinkData {
  const ChatDeepLinkData({
    required this.roomId,
    required this.threadId,
    this.roomName,
    this.rawData = const {},
  });

  final String roomId;
  final String threadId;
  final String? roomName;
  final Map<String, dynamic> rawData;

  /// Trích xuất dữ liệu từ Map (payload của OneSignal additionalData hoặc custom JSON).
  ///
  /// Hỗ trợ cả camelCase (`roomId`), snake_case (`room_id`), và PascalCase (`RoomId`).
  /// Trả về `null` nếu dữ liệu thiếu cả `roomId` lẫn `threadId`.
  static ChatDeepLinkData? fromMap(Map<dynamic, dynamic>? map) {
    if (map == null || map.isEmpty) return null;

    final data = map.cast<String, dynamic>();

    final roomId = (data['roomId'] ??
            data['room_id'] ??
            data['RoomId'] ??
            data['conversationId'] ??
            data['conversation_id'])
        ?.toString()
        .trim();

    final threadId = (data['threadId'] ??
            data['thread_id'] ??
            data['ThreadId'] ??
            roomId)
        ?.toString()
        .trim();

    final roomName = (data['roomName'] ??
            data['room_name'] ??
            data['RoomName'] ??
            data['title'])
        ?.toString()
        .trim();

    if ((roomId == null || roomId.isEmpty) &&
        (threadId == null || threadId.isEmpty)) {
      return null;
    }

    final finalRoomId = (roomId != null && roomId.isNotEmpty)
        ? roomId
        : threadId!;
    final finalThreadId = (threadId != null && threadId.isNotEmpty)
        ? threadId
        : finalRoomId;

    return ChatDeepLinkData(
      roomId: finalRoomId,
      threadId: finalThreadId,
      roomName: roomName?.isNotEmpty == true ? roomName : null,
      rawData: data,
    );
  }
}

/// Helper tiện ích điều hướng mở màn hình trong Chat Module.
class ChatNavigator {
  const ChatNavigator._();

  static ThreadScreenBuilder? threadScreenBuilder;

  /// Mở trực tiếp màn hình phòng chat.
  static Future<T?> openThread<T>(
    BuildContext context, {
    required String roomId,
    required String threadId,
    required String currentUserId,
    String? title,
    String? senderAvatarUrl,
    ThreadScreenBuilder? builder,
  }) {
    final activeBuilder = builder ?? threadScreenBuilder;
    if (activeBuilder == null) {
      throw StateError(
        'ChatNavigator.threadScreenBuilder chưa được đăng ký. '
        'Hãy gán ChatNavigator.threadScreenBuilder hoặc truyền builder vào openThread.',
      );
    }
    return Navigator.of(context).push<T>(
      MaterialPageRoute<T>(
        builder: (ctx) => activeBuilder(
          ctx,
          roomId: roomId,
          threadId: threadId,
          currentUserId: currentUserId,
          title: title,
          senderAvatarUrl: senderAvatarUrl,
        ),
      ),
    );
  }

  /// Tự động trích xuất payload notification và điều hướng tới phòng chat tương ứng.
  ///
  /// Trả về `true` nếu trích xuất và điều hướng thành công, `false` nếu payload không hợp lệ.
  static Future<bool> openFromDeepLink(
    BuildContext context,
    Map<dynamic, dynamic>? payload, {
    required String currentUserId,
  }) async {
    final deepLink = ChatDeepLinkData.fromMap(payload);
    if (deepLink == null) return false;

    await openThread<void>(
      context,
      roomId: deepLink.roomId,
      threadId: deepLink.threadId,
      title: deepLink.roomName,
      currentUserId: currentUserId,
    );
    return true;
  }
}
