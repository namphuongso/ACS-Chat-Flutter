import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Trạng thái online/offline của thiết bị — dùng cho offline banner.
///
/// `StreamProvider` (không phải `Notifier`) vì đây là nguồn ngoài (plugin),
/// không phải state do app điều khiển. `.value` = `null` khi chưa có kết quả
/// đầu tiên → UI nên coi là online (default true).
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  final initial = await connectivity.checkConnectivity();
  yield _hasConnection(initial);
  await for (final result in connectivity.onConnectivityChanged) {
    yield _hasConnection(result);
  }
});

bool _hasConnection(List<ConnectivityResult> results) {
  return results.any((r) => r != ConnectivityResult.none);
}
