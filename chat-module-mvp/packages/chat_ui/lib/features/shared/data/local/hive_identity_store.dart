import 'package:hive/hive.dart';

/// Lưu `acsUserId` của bản thân (thuộc tính cố định theo user — giống nhau ở
/// MỌI room) để khôi phục nhanh khi mở màn hình chat, không phải chờ
/// join-room mới biết "tôi là ai".
///
/// Trước đây identity chỉ nằm trong RAM của `AuthTokenRepository` → lần vào
/// đầu của session: myAcsUserId = null → tin nhắn render sai phía (mọi tin
/// `isMe=false`) hoặc phải chờ join-room (chậm → cảm giác kẹt loading), phải
/// back ra vô lại mới đúng. Lưu xuống disk keyed theo `currentUserId` (an toàn
/// khi đổi tài khoản), restore là đọc local — tức thì, không cần mạng.
///
/// Box mở lazily; nếu Hive chưa init (vd test) thì no-op, module vẫn chạy.
class HiveIdentityStore {
  HiveIdentityStore({Box<String>? box}) : _box = box;

  Box<String>? _box;
  bool _unavailable = false;

  static const _boxName = 'chat_identity';

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

  static String _key(String userId) => 'my_acs_user_id:$userId';

  Future<String?> getMyAcsUserId(String userId) async {
    final box = await _activeBox();
    if (box == null) return null;
    final v = box.get(_key(userId));
    return (v is String && v.isNotEmpty) ? v : null;
  }

  String? getMyAcsUserIdSync(String userId) {
    if (_unavailable) return null;
    if (_box != null) {
      final v = _box!.get(_key(userId));
      return (v is String && v.isNotEmpty) ? v : null;
    }
    try {
      if (Hive.isBoxOpen(_boxName)) {
        _box = Hive.box<String>(_boxName);
        final v = _box!.get(_key(userId));
        return (v is String && v.isNotEmpty) ? v : null;
      }
    } catch (_) {
      _unavailable = true;
    }
    return null;
  }

  Future<void> setMyAcsUserId(String userId, String? value) async {
    final box = await _activeBox();
    if (box == null) return;
    if (value == null || value.isEmpty) {
      await box.delete(_key(userId));
    } else {
      await box.put(_key(userId), value);
    }
  }

  Future<void> clearUserData(String userId) async {
    final box = await _activeBox();
    if (box == null) return;
    await box.delete(_key(userId));
  }
}
