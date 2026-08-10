/// Host app (app tích hợp module chat) implement interface này để cung
/// cấp Bearer token xác thực app (KHÔNG phải ACS token — xem api-docs
/// mục 1.2). Module chat không tự biết app đăng nhập bằng cách nào.
abstract class ChatAuthTokenProvider {
  /// Trả về app JWT hiện tại còn hạn. Nếu hết hạn, provider tự refresh
  /// (module chat không quản lý refresh app-level token, chỉ quản lý
  /// refresh ACS token thông qua provider này).
  Future<String> getAppToken();
}
