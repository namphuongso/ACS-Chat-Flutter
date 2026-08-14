import 'package:chat_core/chat_core.dart';
import 'package:html/parser.dart' as html_parser;

/// Helper format preview tin nhắn cuối trong danh sách hội thoại.
class LastMessagePreview {
  static final _tagRegex = RegExp(r'<[a-zA-Z][^>]*>');

  /// Hiển thị nội dung plain text (loại bỏ các thẻ HTML) của tin nhắn cuối.
  static String format(Conversation conversation) {
    final summary = conversation.lastMessage;
    if (summary == null) return '';
    return cleanContent(summary.content);
  }

  /// Loại bỏ các thẻ HTML và unescape các thực thể HTML để trả về chuỗi text thuần túy.
  static String cleanContent(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return '';
    final unescaped = _maybeUnescape(raw);
    if (!_tagRegex.hasMatch(unescaped)) {
      return unescaped.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    try {
      final withSpaces = unescaped.replaceAll(
        RegExp(r'</?(div|p|h[1-6]|li|blockquote|br)[^>]*>', caseSensitive: false),
        ' ',
      );
      final doc = html_parser.parse(withSpaces);
      final plainText = doc.body?.text ?? withSpaces;
      return plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
    } catch (_) {
      return unescaped
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
  }

  static String _maybeUnescape(String raw) {
    if (!raw.contains('&')) return raw;
    return raw
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
  }
}
