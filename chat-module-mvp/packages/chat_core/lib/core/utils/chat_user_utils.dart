/// Utility xử lý chuẩn hóa và so sánh ID người dùng trong Chat Module.
class ChatUserUtils {
  const ChatUserUtils._();

  /// Chuẩn hóa chuỗi User ID bằng cách cắt bỏ tiền tố `8:acs:` (nếu có) và trích xuất
  /// phần unique userId phía sau dấu `_` (nếu có).
  static String normalizeUserId(String rawId) {
    if (rawId.isEmpty) return '';
    var clean = rawId.trim();
    if (clean.startsWith('8:acs:')) {
      clean = clean.substring(6);
    }
    final lastUnderscoreIdx = clean.lastIndexOf('_');
    if (lastUnderscoreIdx != -1 && lastUnderscoreIdx < clean.length - 1) {
      clean = clean.substring(lastUnderscoreIdx + 1);
    }
    return clean.toLowerCase();
  }

  /// Alias tương thích ngược cho normalizeUserId.
  static String normalizeAcsId(String rawId) => normalizeUserId(rawId);

  /// So sánh hai User ID có thuộc về cùng một người dùng hay không.
  static bool isSameUser(String rawId1, String rawId2) {
    if (rawId1.isEmpty || rawId2.isEmpty) return false;
    final norm1 = normalizeUserId(rawId1);
    final norm2 = normalizeUserId(rawId2);
    if (norm1.isEmpty || norm2.isEmpty) return false;
    return norm1 == norm2;
  }

  /// Alias tương thích ngược cho isSameUser.
  static bool isSameAcsUser(String rawId1, String rawId2) =>
      isSameUser(rawId1, rawId2);
}

/// Alias tương thích ngược cho tên lớp cũ.
typedef AcsUserUtils = ChatUserUtils;
