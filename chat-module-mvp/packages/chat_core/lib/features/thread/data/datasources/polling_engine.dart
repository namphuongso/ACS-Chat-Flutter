import 'dart:async';
import 'dart:math';

import '../../domain/entities/message.dart';

/// Implement đúng biện pháp giảm thiểu rủi ro rate-limit ở mục 5 kế hoạch
/// gốc:
/// 1. Interval thích ứng theo participant (MVP luôn dùng [baseInterval]
///    vì direct conversation chỉ có 2 người).
/// 2. Jitter ngẫu nhiên 0-1s khi khởi động, tránh đồng bộ hoá vô tình.
/// 3. Dùng [startTime] thay vì lấy nguyên trang mỗi lần.
/// 4. Exponential backoff khi gặp 429.
/// 5. Chỉ 1 timer cho 1 threadId, dừng hẳn qua [stop].
class PollingEngine<T extends Message> {
  PollingEngine({
    required this.threadId,
    required this.baseInterval,
    required Future<List<T>> Function({required String? startTime})
        fetchNewMessages,
  }) : _fetch = fetchNewMessages;

  final String threadId;
  final Duration baseInterval;
  final Future<List<T>> Function({required String? startTime}) _fetch;

  Timer? _timer;
  DateTime? _lastFetchTime;
  int _consecutiveErrors = 0;
  final _controller = StreamController<T>.broadcast();
  bool _isRunning = false;

  Stream<T> get stream => _controller.stream;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    final jitter = Duration(milliseconds: Random().nextInt(1000));
    Timer(jitter, _scheduleNext);
  }

  void _scheduleNext() {
    if (!_isRunning) return;
    final interval = _currentInterval();
    _timer = Timer(interval, _tick);
  }

  Duration _currentInterval() {
    if (_consecutiveErrors == 0) return baseInterval;
    // Exponential backoff khi gặp lỗi liên tiếp (chủ yếu 429), trần 60s
    // để không polling quá thưa nếu mạng chỉ lỗi tạm thời.
    final backoffSeconds =
        min(60, baseInterval.inSeconds * pow(2, _consecutiveErrors).toInt());
    return Duration(seconds: backoffSeconds);
  }

  Future<void> _tick() async {
    if (!_isRunning) return;
    try {
      final startTime = _lastFetchTime?.toIso8601String();
      final newMessages = await _fetch(startTime: startTime);
      _consecutiveErrors = 0;
      _lastFetchTime = DateTime.now();
      for (final m in newMessages) {
        if (!_controller.isClosed) _controller.add(m);
      }
    } catch (e) {
      _consecutiveErrors++;
      // Không rethrow — polling phải tự phục hồi, không được làm chết
      // luồng UI đang lắng nghe stream này.
    } finally {
      _scheduleNext();
    }
  }

  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    stop();
    await _controller.close();
  }
}
