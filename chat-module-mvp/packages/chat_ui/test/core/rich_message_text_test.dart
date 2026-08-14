import 'package:chat_ui/chat_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String _plainText(InlineSpan span, [String acc = '']) {
    if (span is TextSpan) {
      var text = acc + (span.text ?? '');
      for (final child in span.children ?? const []) {
        text = _plainText(child, text);
      }
      return text;
    }
    return acc;
  }

  bool _anyStyle(InlineSpan span, bool Function(TextStyle?) test) {
    if (span is TextSpan) {
      if (test(span.style)) return true;
      for (final child in span.children ?? const []) {
        if (_anyStyle(child, test)) return true;
      }
    }
    return false;
  }

  group('RichMessageText', () {
    testWidgets('render plain text khi không có thẻ HTML', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RichMessageText(
              content: 'Xin chào',
              style: TextStyle(fontSize: 15),
            ),
          ),
        ),
      );

      expect(find.text('Xin chào'), findsOneWidget);
    });

    testWidgets('render sample rich text web không crash', (tester) async {
      const sample =
          '<b>12</b><i>34</i><u>56</u><strike>89'
          '<font size="2">12</font><font size="3">34</font>'
          '<font size="5">56</font><font size="7">78'
          '<font color="#ef4444">12</font><font color="#f97316">34</font>'
          '<font color="#eab308">56</font><font color="#22c55e">67</font>'
          '</font></strike></u></i></b>'
          '<div><ul><li><b><i><u><strike><font size="7" color="#0f172a">12'
          '</font></strike></u></i></b></li>'
          '<li><b><i><u><strike><font color="#0f172a" size="3">23</font>'
          '</strike></u></i></b></li></ul>'
          '<ol><li><font color="#0f172a" size="3"><b><i><u><strike>12'
          '</strike></u></i></b></font></li>'
          '<li><font color="#0f172a" size="3"><b><i><u><strike>45</strike>'
          '</u></i></b></font></li></ol></div>'
          '<blockquote><div><font color="#0f172a" size="3"><b><i><u>'
          '<strike>12</strike></u></i></b></font></div></blockquote>'
          '<blockquote><blockquote><div><font color="#0f172a" size="3">'
          '<b><i><u><strike>34</strike></u></i></b></font></div>'
          '</blockquote></blockquote>';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RichMessageText(
                content: sample,
                style: TextStyle(fontSize: 15),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.byType(Text));
      final span = text.textSpan!;
      expect(_plainText(span), isNot(contains('<')));
      expect(_plainText(span), contains('12'));
      // Có span bold, italic, underline, strike, đổi cỡ chữ và màu.
      expect(_anyStyle(span, (s) => s?.fontWeight == FontWeight.bold), isTrue);
      expect(_anyStyle(span, (s) => s?.fontStyle == FontStyle.italic), isTrue);
      expect(
        _anyStyle(
          span,
          (s) =>
              s?.decoration == TextDecoration.underline ||
              (s?.decoration?.contains(TextDecoration.underline) ?? false),
        ),
        isTrue,
      );
      expect(
        _anyStyle(
          span,
          (s) =>
              s?.decoration == TextDecoration.lineThrough ||
              (s?.decoration?.contains(TextDecoration.lineThrough) ?? false),
        ),
        isTrue,
      );
      expect(
        _anyStyle(span, (s) => s?.fontSize == 30.0 || s?.fontSize == 13.0),
        isTrue,
      );
      expect(
        _anyStyle(
          span,
          (s) =>
              s?.color == const Color(0xFFef4444) ||
              s?.color == const Color(0xFF22c55e),
        ),
        isTrue,
      );
    });

    testWidgets('render HTML bị escape (entity) như richtext', (tester) async {
      const escaped = '&lt;b&gt;12&lt;/b&gt; &lt;i&gt;34&lt;/i&gt;';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RichMessageText(
              content: escaped,
              style: TextStyle(fontSize: 15),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.byType(Text));
      final span = text.textSpan!;
      expect(_plainText(span), isNot(contains('&lt;')));
      expect(
        _anyStyle(span, (s) => s?.fontWeight == FontWeight.bold),
        isTrue,
      );
      expect(
        _anyStyle(span, (s) => s?.fontStyle == FontStyle.italic),
        isTrue,
      );
    });

    testWidgets('render span style="..." (CSS inline) + thụt lề blockquote',
        (tester) async {
      const web = '<span style="font-weight: bold; color: #ef4444">Đỏ đậm'
          '</span> <span style="text-decoration: line-through;">gạch ngang'
          '</span><span style="font-style: italic;"> nghiêng</span>'
          '<blockquote><div><span style="color:#0f172a">dòng 1</span></div>'
          '<div><span style="color:#0f172a">dòng 2</span></div></blockquote>';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RichMessageText(
              content: web,
              style: TextStyle(fontSize: 15),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.byType(Text));
      final span = text.textSpan!;
      // span bold + màu
      expect(
        _anyStyle(
          span,
          (s) => s?.fontWeight == FontWeight.bold && s?.color == const Color(0xFFef4444),
        ),
        isTrue,
      );
      // span text-decoration: line-through
      expect(
        _anyStyle(
          span,
          (s) => s?.decoration == TextDecoration.lineThrough ||
              (s?.decoration?.contains(TextDecoration.lineThrough) ?? false),
        ),
        isTrue,
      );
      // span font-style italic
      expect(
        _anyStyle(span, (s) => s?.fontStyle == FontStyle.italic),
        isTrue,
      );
      // Blockquote thụt lề 2 dòng
      final plain = _plainText(span);
      expect(plain, contains('\n  dòng 1'));
      expect(plain, contains('dòng 1\n  dòng 2'));
    });
  });
}
