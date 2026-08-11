import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cấu hình màu sắc của module chat (màn hình trò chuyện) — do host app
/// (vd NPP-Mobile) quyết định.
///
/// Mặc định dùng theme Material của host app. Nếu host muốn tự quyết màu,
/// override `chatUiConfigProvider` với instance này — ví dụ:
///
/// ```dart
/// chatUiConfigProvider.overrideWithValue(ChatUiConfig(
///   sentBubbleColor: AppColors.chatSent,
///   receivedBubbleColor: AppColors.chatReceived,
///   roomBackgroundColor: AppColors.chatBackground,
///   inputBarBackgroundColor: AppColors.chatInputBar,
///   iconColor: AppColors.chatIcon,
/// ));
/// ```
class ChatUiConfig {
  const ChatUiConfig({
    this.sentBubbleColor,
    this.sentTextColor,
    this.receivedBubbleColor,
    this.receivedTextColor,
    this.roomBackgroundColor,
    this.appBarBackgroundColor,
    this.iconColor,
    this.inputBarBackgroundColor,
    this.inputFieldFillColor,
    this.inputFieldBorderColor,
    this.inputTextColor,
    this.inputHintColor,
    this.searchBarFillColor,
    this.searchBarIconColor,
    this.searchBarTextColor,
    this.searchBarHintColor,
  });

  /// Màu nền bubble tin nhắn của mình (bên phải). `null` = fallback theme.
  final Color? sentBubbleColor;

  /// Màu chữ/icon trong bubble của mình. `null` = fallback theme
  /// (`onPrimary`). Truyền cùng [sentBubbleColor] nếu bubble sáng (vd vàng)
  /// để chữ không bị loá.
  final Color? sentTextColor;

  /// Màu nền bubble tin nhắn của người khác (bên trái). `null` = fallback theme.
  final Color? receivedBubbleColor;

  /// Màu chữ/icon trong bubble của người khác. `null` = fallback theme
  /// (`onSurface`).
  final Color? receivedTextColor;

  /// Nền của màn hình trò chuyện (vùng hiển thị tin nhắn). `null` = fallback
  /// theme (`scaffoldBackgroundColor`).
  final Color? roomBackgroundColor;

  /// Nền của AppBar (tiêu đề room + icon). `null` = fallback theme.
  final Color? appBarBackgroundColor;

  /// Màu icon chung (AppBar, nút gửi, ...). `null` = fallback theme.
  final Color? iconColor;

  /// Nền của khung input chat (vùng chứa ô nhập + nút gửi). `null` = fallback
  /// theme (`surface`).
  final Color? inputBarBackgroundColor;

  /// Nền ô nhập tin nhắn (TextField). `null` = fallback theme.
  final Color? inputFieldFillColor;

  /// Màu viền ô nhập tin nhắn. `null` = fallback theme.
  final Color? inputFieldBorderColor;

  /// Màu chữ gõ vào ô nhập. `null` = fallback theme.
  final Color? inputTextColor;

  /// Màu hint (`Nhập tin nhắn...`). `null` = fallback theme.
  final Color? inputHintColor;

  /// Nền ô tìm kiếm (SearchField). `null` = fallback theme.
  final Color? searchBarFillColor;

  /// Màu icon tìm kiếm/xoá. `null` = fallback theme.
  final Color? searchBarIconColor;

  /// Màu chữ trong ô tìm kiếm. `null` = fallback theme.
  final Color? searchBarTextColor;

  /// Màu hint trong ô tìm kiếm. `null` = fallback theme.
  final Color? searchBarHintColor;
}

/// Provider cấu hình UI. Host app có thể override để đổi màu bubble.
final chatUiConfigProvider = Provider<ChatUiConfig>((ref) {
  return const ChatUiConfig();
});