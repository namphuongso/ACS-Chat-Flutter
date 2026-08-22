class AcsUserUtils {
  const AcsUserUtils._();

  /// Chuẩn hóa chuỗi ACS User ID bằng cách cắt bỏ tiền tố `8:acs:` và trích xuất
  /// phần unique userId phía sau dấu `_` (nếu có).
  static String normalizeAcsId(String rawId) {
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

  /// So sánh hai ACS User ID có thuộc về cùng một người dùng hay không.
  static bool isSameAcsUser(String rawId1, String rawId2) {
    if (rawId1.isEmpty || rawId2.isEmpty) return false;
    final norm1 = normalizeAcsId(rawId1);
    final norm2 = normalizeAcsId(rawId2);
    if (norm1.isEmpty || norm2.isEmpty) return false;
    return norm1 == norm2;
  }
}
