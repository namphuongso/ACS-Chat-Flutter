import 'dart:convert';

import 'package:chat_core/chat_core.dart';
import 'package:hive/hive.dart';

/// Cache danh sách conversation bằng Hive — lưu dưới dạng JSON string.
///
/// Mở box lazily (lần dùng đầu tiên). Yêu cầu host app đã gọi
/// `Hive.initFlutter()` (NPP main đã gọi). Nếu box không mở được (Hive chưa
/// init), mọi thao tác trở thành no-op → module vẫn chạy, chỉ mất cache.
class HiveConversationLocalDataSource implements ConversationLocalDataSource {
  HiveConversationLocalDataSource({Box<String>? box}) : _box = box;

  Box<String>? _box;
  bool _unavailable = false;

  static const _boxName = 'chat_conversations';
  static const _key = 'conversations';

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
  Future<List<Conversation>> getCachedConversations() async {
    final box = await _activeBox();
    if (box == null) return const [];
    final raw = box.get(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => _conversationFromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveConversations(List<Conversation> conversations) async {
    final box = await _activeBox();
    if (box == null) return;
    final encoded = jsonEncode(conversations.map(_conversationToJson).toList());
    await box.put(_key, encoded);
  }

  @override
  Future<void> clear() async {
    final box = await _activeBox();
    if (box == null) return;
    await box.delete(_key);
  }

  Map<String, dynamic> _conversationToJson(Conversation c) => {
        'id': c.id,
        'threadId': c.threadId,
        'type': c.type.name,
        'participants': c.participants.map(_userToJson).toList(),
        'createdAt': c.createdAt.toIso8601String(),
        'updatedAt': c.updatedAt.toIso8601String(),
        'roomName': c.roomName,
        'avatarUrl': c.avatarUrl,
        'pid': c.pid,
        'pin': c.pin,
        'isMuted': c.isMuted,
        'unreadCount': c.unreadCount,
        'lastMessage': c.lastMessage == null
            ? null
            : {
                'content': c.lastMessage!.content,
                'senderDisplayName': c.lastMessage!.senderDisplayName,
                'senderId': c.lastMessage!.senderId,
                'createdAt': c.lastMessage!.createdAt.toIso8601String(),
              },
      };

  Conversation _conversationFromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        threadId: j['threadId'] as String,
        type: j['type'] == ConversationType.group.name
            ? ConversationType.group
            : ConversationType.direct,
        participants: ((j['participants'] as List?) ?? [])
            .map((e) => _userFromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        updatedAt: DateTime.parse(j['updatedAt'] as String).toLocal(),
        roomName: j['roomName'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        pid: j['pid'] as String?,
        pin: j['pin'] as bool? ?? false,
        isMuted: j['isMuted'] as bool? ?? false,
        unreadCount: j['unreadCount'] as int? ?? 0,
        lastMessage: j['lastMessage'] == null
            ? null
            : ConversationSummary(
                content: (j['lastMessage'] as Map)['content'] as String? ?? '',
                senderDisplayName:
                    (j['lastMessage'] as Map)['senderDisplayName'] as String? ??
                        '',
                senderId: (j['lastMessage'] as Map)['senderId'] as String?,
                createdAt: DateTime.parse(
                        (j['lastMessage'] as Map)['createdAt'] as String)
                    .toLocal(),
              ),
      );

  Map<String, dynamic> _userToJson(ChatUser u) => {
        'id': u.id,
        'displayName': u.displayName,
        'avatarUrl': u.avatarUrl,
        'acsUserId': u.acsUserId,
        'email': u.email,
      };

  ChatUser _userFromJson(Map<String, dynamic> j) => ChatUser(
        id: j['id'] as String,
        displayName: j['displayName'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        acsUserId: j['acsUserId'] as String?,
        email: j['email'] as String?,
      );
}
