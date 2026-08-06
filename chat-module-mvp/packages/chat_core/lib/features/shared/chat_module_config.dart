/// Cấu hình module — theo mục 7.2 kế hoạch gốc: "mọi field mới
/// nullable/có default" để thêm option sau này không breaking consumer
/// đang dùng version cũ.
class ChatModuleConfig {
  const ChatModuleConfig({
    required this.backendBaseUrl,
    this.pollingIntervalSmallGroup = const Duration(seconds: 4),
    this.pollingIntervalLargeGroup = const Duration(seconds: 12),
    this.largeGroupThreshold = 20,
    this.enableSendTyping = false,
  });

  /// Base URL của BE nội bộ, vd `https://api.example.com/api`.
  final String backendBaseUrl;

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
}
