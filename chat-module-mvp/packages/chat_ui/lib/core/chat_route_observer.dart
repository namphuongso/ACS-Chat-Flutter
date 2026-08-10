import 'package:flutter/widgets.dart';

/// Observer dùng chung để chat_ui tự refresh khi quay lại màn hình
/// (vd: danh sách phòng refresh tin cuối khi back từ màn hình chat).
/// Host app đăng ký vào `MaterialApp.navigatorObservers`.
final RouteObserver<ModalRoute<void>> chatRouteObserver =
    RouteObserver<ModalRoute<void>>();
