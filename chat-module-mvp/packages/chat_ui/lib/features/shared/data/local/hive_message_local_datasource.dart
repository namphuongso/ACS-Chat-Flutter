import 'dart:convert';

import 'package:chat_core/chat_core.dart';
import 'package:hive/hive.dart';

/// Cache tin nhắn bằng Hive — lưu dưới dạng JSON string theo threadId.
///
/// Mở box lazily (lần dùng đầu tiên). Yêu cầu host app đã gọi
/// `Hive.initFlutter()` (NPP main đã gọi). Nếu box không mở được (Hive chưa
/// init), mọi thao tác trở thành no-op → module vẫn chạy, chỉ mất cache.
class HiveMessageLocalDataSource implements MessageLocalDataSource {
  HiveMessageLocalDataSource({
    this.userId,
    Box<String>? box,
  }) : _box = box;

  final String? userId;
  Box<String>? _box;
  bool _unavailable = false;

  static const _boxName = 'chat_messages';

  String _key(String threadId) {
    if (userId != null && userId!.isNotEmpty) {
      return '$userId:$threadId';
    }
    return threadId;
  }

  Future<Box<String>?> _activeBox() async {
    if (_unavailable) return null;
    if (_box != null) return _box;
    try {
      if (Hive.isBoxOpen(_boxName)) {
        _box = Hive.box<String>(_boxName);
      } else {
        _box = await Hive.openBox<String>(_boxName);
      }
    } catch (_) {
      _unavailable = true;
      return null;
    }
    return _box;
  }

  @override
  Future<List<Message>> getCachedMessages(String threadId) async {
    final box = await _activeBox();
    if (box == null) return const [];
    final raw = box.get(_key(threadId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => _messageFromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveMessages(String threadId, List<Message> messages) async {
    final box = await _activeBox();
    if (box == null) return;
    final encoded = jsonEncode(messages.map(_messageToJson).toList());
    await box.put(_key(threadId), encoded);
  }

  @override
  Future<void> clear(String threadId) async {
    final box = await _activeBox();
    if (box == null) return;
    await box.delete(_key(threadId));
  }

  Future<void> clearAllUserData(String targetUserId) async {
    final box = await _activeBox();
    if (box == null) return;
    final prefix = '$targetUserId:';
    final keysToDelete = box.keys
        .whereType<String>()
        .where((k) => k.startsWith(prefix))
        .toList();
    for (final key in keysToDelete) {
      await box.delete(key);
    }
  }

  Map<String, dynamic> _messageToJson(Message m) => {
        'id': m.id,
        'threadId': m.threadId,
        'senderId': m.senderId,
        'senderDisplayName': m.senderDisplayName,
        'content': m.content,
        'type': m.type.value,
        'createdAt': m.createdAt.toIso8601String(),
        'status': m.status.name,
        'metadata': m.metadata,
        'pin': m.pin,
        'deletedOn': m.deletedOn?.toIso8601String(),
      };

  Message _messageFromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        threadId: j['threadId'] as String,
        senderId: j['senderId'] as String? ?? '',
        senderDisplayName: j['senderDisplayName'] as String? ?? '',
        content: j['content'] as String? ?? '',
        type: MessageType.fromString(j['type'] as String? ?? 'text'),
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        status:
            MessageDeliveryStatus.values.asNameMap()[j['status'] as String?] ??
                MessageDeliveryStatus.sent,
        metadata: (j['metadata'] as Map?)?.cast<String, dynamic>(),
        pin: j['pin'] as bool? ?? false,
        deletedOn: j['deletedOn'] != null
            ? DateTime.parse(j['deletedOn'] as String).toLocal()
            : null,
      );
}
