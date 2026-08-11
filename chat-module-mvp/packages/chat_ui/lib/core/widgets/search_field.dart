import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Thanh tìm kiếm dùng chung cho module chat (tìm phòng chat, tìm danh bạ).
///
/// - Thiết kế pill, nền nhạt, icon search + nút xoá khi đã nhập chữ.
/// - [onSearch] được gọi sau [debounceDuration] kể từ lần gõ cuối (mặc định
///   350ms), hoặc ngay khi bấm "Search" trên bàn phím / nút xoá — tránh gọi
///   API/filter liên tục theo từng ký tự.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.hintText,
    required this.onSearch,
    this.debounceDuration = const Duration(milliseconds: 350),
    this.controller,
    this.autofocus = false,
    this.fillColor,
    this.iconColor,
    this.textColor,
    this.hintColor,
  });

  final String hintText;

  /// Nhận keyword (đã trim) sau khi debounce / submit / clear.
  final ValueChanged<String> onSearch;

  final Duration debounceDuration;

  /// Controller tuỳ chọn — nếu không truyền, widget tự tạo và dispose.
  final TextEditingController? controller;

  final bool autofocus;

  final Color? fillColor;
  final Color? iconColor;
  final Color? textColor;
  final Color? hintColor;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDuration, () {
      widget.onSearch(text.trim());
    });
  }

  void _submit(String text) {
    _debounce?.cancel();
    widget.onSearch(text.trim());
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    widget.onSearch('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fillColor = widget.fillColor ??
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final iconColor = widget.iconColor ?? theme.colorScheme.onSurfaceVariant;
    final textColor = widget.textColor ?? theme.colorScheme.onSurface;
    final hintColor = widget.hintColor ?? theme.colorScheme.onSurfaceVariant;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(Icons.search_rounded, size: 22, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _submit,
              style: TextStyle(color: textColor, fontSize: 15),
              cursorColor: iconColor,
              inputFormatters: [LengthLimitingTextInputFormatter(100)],
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(color: hintColor, fontSize: 15),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final hasText = value.text.isNotEmpty;
              return hasText
                  ? IconButton(
                      onPressed: _clear,
                      tooltip: 'Xoá tìm kiếm',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded, size: 20, color: iconColor),
                    )
                  : const SizedBox(width: 48);
            },
          ),
        ],
      ),
    );
  }
}
