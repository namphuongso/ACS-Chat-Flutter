class AcsUserUtils {
  const AcsUserUtils._();

  /// Chuẩn hóa chuỗi ACS User ID bằng cách cắt bỏ tiền tố `8:acs:` và hậu tố `_` nếu có.
  static String normalizeAcsId(String rawId) {
    if (rawId.isEmpty) return '';
    var clean = rawId.trim();
    if (clean.startsWith('8:acs:')) {
      clean = clean.substring(6);
    }
    final underscoreIdx = clean.indexOf('_');
    if (underscoreIdx != -1) {
      clean = clean.substring(0, underscoreIdx);
    }
    return clean.toLowerCase();
  }

  /// So sánh hai ACS User ID có thuộc về cùng một người dùng hay không.
  static bool isSameAcsUser(String rawId1, String rawId2) {
    if (rawId1.isEmpty || rawId2.isEmpty) return false;
    return normalizeAcsId(rawId1) == normalizeAcsId(rawId2);
  }
}
