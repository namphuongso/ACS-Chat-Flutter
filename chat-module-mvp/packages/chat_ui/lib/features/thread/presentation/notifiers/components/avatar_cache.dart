import 'package:chat_core/chat_core.dart';
import '../../../../../core/utils/avatar_utils.dart';

/// Bộ nhớ đệm avatar của người dùng với chính sách LRU eviction (tối đa 200 phần tử).
class AvatarCache {
  AvatarCache({this.capacity = 200});

  final int capacity;
  final Map<String, String> _cache = {};

  void cacheUserAvatar(String userId, String avatarUrl) {
    if (userId.isEmpty || avatarUrl.isEmpty || !isNetworkAvatar(avatarUrl)) {
      return;
    }
    final norm = AcsUserUtils.normalizeAcsId(userId);
    if (norm.isNotEmpty) {
      if (_cache.length >= capacity && !_cache.containsKey(norm)) {
        _cache.remove(_cache.keys.first);
      }
      _cache[norm] = avatarUrl;
    }
  }

  String? getAvatarUrlForUser(String userId) {
    if (userId.isEmpty) return null;
    final norm = AcsUserUtils.normalizeAcsId(userId);
    final cached = _cache[norm];
    if (cached != null && isNetworkAvatar(cached)) {
      return cached;
    }
    return null;
  }

  void cacheParticipantAvatars(List<ChatUser> participants) {
    for (final p in participants) {
      final av = p.avatarUrl;
      if (av != null && isNetworkAvatar(av)) {
        cacheUserAvatar(p.id, av);
        final acs = p.acsUserId;
        if (acs != null && acs.isNotEmpty) {
          cacheUserAvatar(acs, av);
        }
      }
    }
  }

  void clear() => _cache.clear();
}
