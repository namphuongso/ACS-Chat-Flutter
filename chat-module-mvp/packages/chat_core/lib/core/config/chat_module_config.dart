/// Cấu hình module — theo mục 7.2 kế hoạch gốc: "mọi field mới
/// nullable/có default" để thêm option sau này không breaking consumer
/// đang dùng version cũ.
class ChatModuleConfig {
  const ChatModuleConfig({
    required this.backendBaseUrl,
    required this.acsEndpoint,
    this.apiKey,
    this.pollingIntervalSmallGroup = const Duration(seconds: 4),
    this.pollingIntervalLargeGroup = const Duration(seconds: 12),
    this.largeGroupThreshold = 20,
    this.enableSendTyping = false,
    this.webSocketUrl,
    this.webSocketTokenQueryParameter = 'access_token',
    this.deviceId,
    this.onSessionExpired,
  });

  /// Base URL của BE nội bộ, vd `https://api.example.com/api`.
  final String backendBaseUrl;

  /// API Key xác thực cho backend headers (truyền qua X-API-KEY).
  final String? apiKey;

  /// Địa chỉ REST API Endpoint của Azure Communication Services, vd `https://my-acs.communication.azure.com`
  final String acsEndpoint;

  /// Interval polling cho nhóm nhỏ (mục 5 kế hoạch gốc: 3-5s).
  /// MVP chỉ có direct conversation (2 người) nên luôn dùng interval này.
  final Duration pollingIntervalSmallGroup;

  /// Interval polling cho nhóm >[largeGroupThreshold] participant.
  /// Chưa dùng ở MVP (chưa có group), để sẵn cho Đợt 1 roadmap.
  final Duration pollingIntervalLargeGroup;

  final int largeGroupThreshold;

  /// Đã tách theo góp ý trước đó: chỉ gửi typing, KHÔNG bao gồm nhận
  /// (nhận typing bắt buộc native, không có ở đây).
  final bool enableSendTyping;

  /// URL WebSocket đầy đủ. Nếu bỏ trống, module suy ra từ origin của
  /// [backendBaseUrl] với path `/ws/chat/view`.
  final String? webSocketUrl;

  /// Tên query parameter dùng truyền app JWT khi WebSocket handshake.
  final String webSocketTokenQueryParameter;

  /// ID ổn định của thiết bị do app chính quản lý và truyền vào.
  /// Nếu bỏ trống, module sinh ID tạm cho vòng đời process hiện tại.
  final String? deviceId;

  /// Được gọi khi server xác nhận JWT không còn hợp lệ. App chính chịu
  /// trách nhiệm thông báo, đăng xuất và cung cấp token mới sau đăng nhập.
  final void Function()? onSessionExpired;
}
