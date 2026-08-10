/// Chỉ cho phép hiển thị avatar khi URL là http/https hợp lệ.
///
/// BE có thể trả các giá trị rác (VD `file:///string`) làm placeholder —
/// `NetworkImage` với URL đó sẽ ném `No host specified in URI`. Hàm này
/// chặn từ trước để fallback về avatar chữ cái đầu.
bool isNetworkAvatar(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}
