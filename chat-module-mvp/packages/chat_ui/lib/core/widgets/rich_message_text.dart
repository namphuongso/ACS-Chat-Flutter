import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

class _Seg {
  const _Seg(this.text, this.style);
  final String text;
  final TextStyle style;
}

class RichMessageText extends StatefulWidget {
  const RichMessageText({
    super.key,
    required this.content,
    required this.style,
  });

  final String content;
  final TextStyle style;

  @override
  State<RichMessageText> createState() => _RichMessageTextState();
}

class _RichMessageTextState extends State<RichMessageText> {
  static final _tagRegex = RegExp(r'<[a-zA-Z][^>]*>');
  static final _urlRegex = RegExp(r'(https?://[^\s<]+)');

  static const _fontSizes = <int, double>{
    1: 11,
    2: 13,
    3: 15,
    4: 18,
    5: 21,
    6: 25,
    7: 30,
  };

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final text = _maybeUnescape(widget.content);
    if (!_tagRegex.hasMatch(text)) {
      return _buildPlainTextWithLinks(text, widget.style);
    }

    final doc = html_parser.parse(text);
    final bodyNodes = doc.body?.nodes ?? const <dom.Node>[];
    final segs = <_Seg>[];
    for (final node in bodyNodes) {
      final childSegs = _walk(node, widget.style, 0);
      if (childSegs.isEmpty) continue;
      final isBlock =
          node is dom.Element && _isBlockTag(node.localName?.toLowerCase());
      if (isBlock && segs.isNotEmpty && !segs.last.text.endsWith('\n')) {
        segs.add(_Seg('\n', widget.style.copyWith(decoration: TextDecoration.none)));
      }
      segs.addAll(childSegs);
    }

    final spans = segs.isEmpty ? [TextSpan(text: text)] : _buildSpans(segs);
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }

  List<TextSpan> _buildSpans(List<_Seg> segs) {
    final spans = <TextSpan>[];
    String? pendingText;
    TextStyle? pendingStyle;
    var consecutiveNewlines = 0;
    var isDocStart = true;

    for (final seg in segs) {
      if (seg.text.isEmpty) continue;

      var text = seg.text;
      if (text == '\n') {
        if (isDocStart) continue;
        consecutiveNewlines++;
        if (consecutiveNewlines > 2) continue;
      } else {
        if (!text.startsWith('\n')) {
          consecutiveNewlines = 0;
          isDocStart = false;
        }
      }

      if (pendingText != null && pendingStyle == seg.style) {
        pendingText += text;
        continue;
      }
      if (pendingText != null) {
        spans.add(TextSpan(text: pendingText, style: pendingStyle));
      }
      pendingText = text;
      pendingStyle = seg.style;
    }
    if (pendingText != null) {
      var lastText = pendingText;
      while (lastText.endsWith('\n\n')) {
        lastText = lastText.substring(0, lastText.length - 1);
      }
      spans.add(TextSpan(text: lastText, style: pendingStyle));
    }
    return spans;
  }

  bool _isBlockTag(String? tag) {
    if (tag == null) return false;
    return const {
      'div',
      'p',
      'section',
      'article',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'ul',
      'ol',
      'li',
      'blockquote',
      'hr',
    }.contains(tag);
  }

  List<_Seg> _walk(dom.Node node, TextStyle style, int depth) {
    if (node is dom.Text) {
      final collapsed = _collapseSpace(node.text);
      if (collapsed.isEmpty) return const [];
      return [_Seg(collapsed, style)];
    }
    if (node is! dom.Element) return const [];
    final tag = node.localName?.toLowerCase();
    final elem = _elementStyle(style, node);
    final elemStyle = elem.style;

    List<_Seg> withIndent(List<_Seg> segs) {
      if (elem.indentSpaces <= 0 || segs.isEmpty) return segs;
      final indentStyle = elemStyle.copyWith(
        decoration: TextDecoration.none,
        decorationColor: null,
      );
      return [_Seg(' ' * elem.indentSpaces, indentStyle), ...segs];
    }

    List<_Seg> formatBlock(dom.Element n, TextStyle s, int d,
        {double? fontSize, FontWeight? fontWeight}) {
      var st = s;
      if (fontSize != null) st = st.copyWith(fontSize: fontSize);
      if (fontWeight != null) st = st.copyWith(fontWeight: fontWeight);
      final children = _walkChildren(n, st, d);
      if (children.isEmpty) return const [];
      final indented = withIndent(children);
      final out = <_Seg>[...indented];
      if (!indented.last.text.endsWith('\n')) {
        out.add(_Seg('\n', st.copyWith(decoration: TextDecoration.none)));
      }
      return out;
    }

    switch (tag) {
      case 'br':
        return [_Seg('\n', elemStyle)];
      case 'b' || 'strong':
        return withIndent(_walkChildren(
            node, elemStyle.copyWith(fontWeight: FontWeight.bold), depth));
      case 'i' || 'em':
        return withIndent(_walkChildren(
            node, elemStyle.copyWith(fontStyle: FontStyle.italic), depth));
      case 'u':
        return withIndent(_walkChildren(
          node,
          _addDecoration(elemStyle, TextDecoration.underline),
          depth,
        ));
      case 's' || 'strike' || 'del':
        return withIndent(_walkChildren(
          node,
          _addDecoration(elemStyle, TextDecoration.lineThrough),
          depth,
        ));
      case 'h1':
        return formatBlock(node, elemStyle, depth,
            fontSize: 24, fontWeight: FontWeight.bold);
      case 'h2':
        return formatBlock(node, elemStyle, depth,
            fontSize: 20, fontWeight: FontWeight.bold);
      case 'h3':
        return formatBlock(node, elemStyle, depth,
            fontSize: 18, fontWeight: FontWeight.bold);
      case 'h4':
        return formatBlock(node, elemStyle, depth,
            fontSize: 16, fontWeight: FontWeight.bold);
      case 'h5':
        return formatBlock(node, elemStyle, depth,
            fontSize: 14, fontWeight: FontWeight.bold);
      case 'h6':
        return formatBlock(node, elemStyle, depth,
            fontSize: 12, fontWeight: FontWeight.bold);
      case 'div' || 'p' || 'section' || 'article':
        return formatBlock(node, elemStyle, depth);
      case 'ul' || 'ol':
        final listSegs = _walkList(node, elemStyle, depth);
        if (listSegs.isEmpty) return const [];
        final out = <_Seg>[...listSegs];
        if (!out.last.text.endsWith('\n')) {
          out.add(_Seg('\n', elemStyle.copyWith(decoration: TextDecoration.none)));
        }
        return out;
      case 'blockquote':
        final indentedChildren = _indent(
          _walkChildren(node, elemStyle, depth + 1),
          '  ' * (depth + 1),
        );
        if (indentedChildren.isEmpty) return const [];
        final out = <_Seg>[...withIndent(indentedChildren)];
        if (!out.last.text.endsWith('\n')) {
          out.add(_Seg('\n', elemStyle.copyWith(decoration: TextDecoration.none)));
        }
        return out;
      case 'li':
        return withIndent(_walkChildren(node, elemStyle, depth));
      case 'a':
        final linkStyle = _addDecoration(
          elemStyle.copyWith(color: Colors.blue),
          TextDecoration.underline,
        );
        return withIndent(_walkChildren(node, linkStyle, depth));
      case 'code':
        final codeStyle = elemStyle.copyWith(
          fontFamily: 'monospace',
          backgroundColor: Colors.grey.withValues(alpha: 0.15),
        );
        return withIndent(_walkChildren(node, codeStyle, depth));
      default:
        return withIndent(_walkChildren(node, elemStyle, depth));
    }
  }

  List<_Seg> _walkChildren(dom.Element e, TextStyle style, int depth) {
    final out = <_Seg>[];
    for (final child in e.nodes) {
      final childSegs = _walk(child, style, depth);
      if (childSegs.isEmpty) continue;

      final isBlock =
          child is dom.Element && _isBlockTag(child.localName?.toLowerCase());
      if (isBlock && out.isNotEmpty && !out.last.text.endsWith('\n')) {
        out.add(_Seg('\n', style.copyWith(decoration: TextDecoration.none)));
      }
      out.addAll(childSegs);
    }
    return out;
  }

  List<_Seg> _indent(List<_Seg> segs, String indent) {
    if (indent.isEmpty) return segs;
    final out = <_Seg>[];
    var atLineStart = true;
    for (final seg in segs) {
      if (seg.text.isEmpty) continue;
      final parts = seg.text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        final part = parts[i];
        if (i > 0) {
          out.add(_Seg('\n', seg.style.copyWith(decoration: TextDecoration.none)));
        }
        if (part.isEmpty) {
          atLineStart = true;
          continue;
        }
        if (atLineStart) {
          final noDecoStyle = seg.style.copyWith(
            decoration: TextDecoration.none,
            decorationColor: null,
          );
          out.add(_Seg(indent, noDecoStyle));
          out.add(_Seg(part, seg.style));
          atLineStart = false;
        } else {
          out.add(_Seg(part, seg.style));
        }
      }
      if (seg.text.endsWith('\n')) atLineStart = true;
    }
    return out;
  }

  List<_Seg> _walkList(dom.Element e, TextStyle style, int depth) {
    final ordered = e.localName == 'ol';
    final indent = '  ' * depth;
    final prefixStyle = style.copyWith(
      decoration: TextDecoration.none,
      decorationColor: null,
    );
    final out = <_Seg>[];
    var index = 0;
    for (final child in e.nodes) {
      if (child is dom.Element && child.localName == 'li') {
        index++;
        final prefix = '$indent${ordered ? '$index.' : '•'} ';
        out.add(_Seg(prefix, prefixStyle));
        out.addAll(_walk(child, style, depth + 1));
        if (!out.last.text.endsWith('\n')) {
          out.add(_Seg('\n', style.copyWith(decoration: TextDecoration.none)));
        }
      } else {
        out.addAll(_walk(child, style, depth));
      }
    }
    return out;
  }

  ({TextStyle style, int indentSpaces}) _elementStyle(
      TextStyle base, dom.Element e) {
    var s = base;
    var indentSpaces = 0;
    final css = e.attributes['style'];
    if (css != null && css.trim().isNotEmpty) {
      final applied = _applyCss(s, css);
      s = applied.style;
      indentSpaces += applied.indentSpaces;
    }
    final color = e.attributes['color'];
    if (color != null && color.trim().isNotEmpty) {
      final c = _parseColor(color);
      if (c != null) s = s.copyWith(color: c);
    }
    final size = e.attributes['size'];
    if (size != null && size.trim().isNotEmpty) {
      final fs = _mapFontSize(size);
      if (fs != null) s = s.copyWith(fontSize: fs);
    }
    return (style: s, indentSpaces: indentSpaces);
  }

  ({TextStyle style, int indentSpaces}) _applyCss(TextStyle s, String css) {
    var style = s;
    var indentSpaces = 0;
    for (final decl in css.split(';')) {
      final idx = decl.indexOf(':');
      if (idx <= 0) continue;
      final prop = decl.substring(0, idx).trim().toLowerCase();
      final value = decl.substring(idx + 1).trim().toLowerCase();
      switch (prop) {
        case 'font-weight':
          if (value == 'bold' || value == 'bolder') {
            style = style.copyWith(fontWeight: FontWeight.bold);
          } else {
            final w = int.tryParse(value);
            if (w != null) {
              style = style.copyWith(
                fontWeight: w >= 600 ? FontWeight.bold : FontWeight.normal,
              );
            }
          }
        case 'font-style':
          if (value.startsWith('italic') || value.startsWith('oblique')) {
            style = style.copyWith(fontStyle: FontStyle.italic);
          } else if (value == 'normal') {
            style = style.copyWith(fontStyle: FontStyle.normal);
          }
        case 'text-decoration' || 'text-decoration-line':
          if (value == 'none') {
            style = style.copyWith(
              decoration: TextDecoration.none,
              decorationColor: null,
            );
          } else {
            if (value.contains('underline')) {
              style = _addDecoration(style, TextDecoration.underline);
            }
            if (value.contains('line-through')) {
              style = _addDecoration(style, TextDecoration.lineThrough);
            }
            if (value.contains('overline')) {
              style = _addDecoration(style, TextDecoration.overline);
            }
          }
        case 'color':
          final c = _parseColor(value);
          if (c != null) {
            style = style.copyWith(
              color: c,
              decorationColor: style.decoration != null ? c : style.decorationColor,
            );
          }
        case 'font-size':
          final fs = _parseFontSize(value, style.fontSize);
          if (fs != null) style = style.copyWith(fontSize: fs);
        case 'padding-left' ||
              'margin-left' ||
              'text-indent' ||
              'padding' ||
              'margin':
          final px = _parseLeftPx(prop, value);
          if (px != null && px > 0) {
            indentSpaces += px ~/ 8;
          }
      }
    }
    return (style: style, indentSpaces: indentSpaces);
  }

  TextStyle _addDecoration(TextStyle currentStyle, TextDecoration added) {
    final merged = _mergeDecoration(currentStyle.decoration, added);
    final color = currentStyle.color ?? widget.style.color;
    return currentStyle.copyWith(
      decoration: merged,
      decorationColor: color,
    );
  }

  int? _parseLeftPx(String prop, String value) {
    final v = value.trim().toLowerCase();
    if (prop == 'margin-left' ||
        prop == 'padding-left' ||
        prop == 'text-indent') {
      return _parsePx(v);
    }
    if (prop == 'margin' || prop == 'padding') {
      final parts = v.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length == 4) {
        return _parsePx(parts[3]);
      } else if (parts.length == 2 || parts.length == 3) {
        return _parsePx(parts[1]);
      } else if (parts.length == 1) {
        return _parsePx(parts[0]);
      }
    }
    return null;
  }

  double? _parseFontSize(String value, double? base) {
    final val = value.trim().toLowerCase();
    if (val.endsWith('px')) {
      return double.tryParse(val.substring(0, val.length - 2));
    }
    if (val.endsWith('pt')) {
      final pt = double.tryParse(val.substring(0, val.length - 2));
      if (pt != null) return pt * 1.33;
    }
    if (val.endsWith('em') || val.endsWith('rem')) {
      final len = val.endsWith('rem') ? 3 : 2;
      final em = double.tryParse(val.substring(0, val.length - len));
      if (em == null) return null;
      return (base ?? 15) * em;
    }
    if (val.endsWith('%')) {
      final pct = double.tryParse(val.substring(0, val.length - 1));
      if (pct == null) return null;
      return (base ?? 15) * pct / 100;
    }
    switch (val) {
      case 'x-small':
        return 10;
      case 'small':
        return 12;
      case 'medium':
        return 15;
      case 'large':
        return 20;
      case 'x-large':
        return 24;
      case 'xx-large':
        return 30;
    }
    return double.tryParse(val);
  }

  int? _parsePx(String value) {
    final numStr = value.replaceAll(RegExp(r'[^0-9.]'), '');
    final numVal = double.tryParse(numStr);
    if (numVal == null) return null;
    return numVal.toInt();
  }

  TextDecoration _mergeDecoration(
      TextDecoration? current, TextDecoration added) {
    if (current == null) return added;
    if (current.contains(added)) return current;
    return TextDecoration.combine([current, added]);
  }

  Color? _parseColor(String hex) {
    var value = hex.trim().toLowerCase();
    if (value.startsWith('rgb')) {
      final inner = value.replaceAll(RegExp(r'rgba?\(|\)'), '');
      final parts = inner.split(',').map((p) => p.trim()).toList();
      if (parts.length < 3) return null;
      final r = int.tryParse(parts[0]);
      final g = int.tryParse(parts[1]);
      final b = int.tryParse(parts[2]);
      if (r == null || g == null || b == null) return null;
      return Color.fromARGB(
          255, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    }
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 3) {
      value = value.split('').map((c) => c * 2).join();
    }
    if (value.length != 6) return null;
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return null;
    return Color(0xFF000000 | parsed);
  }

  double? _mapFontSize(String sizeAttr) {
    final size = int.tryParse(sizeAttr.trim());
    if (size == null) return null;
    return _fontSizes[size];
  }

  String _collapseSpace(String raw) =>
      raw.replaceAll(RegExp(r'[\r\n\t]+'), ' ');

  String _maybeUnescape(String raw) {
    if (!raw.contains('&')) return raw;
    return raw
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', '\u00a0')
        .replaceAll('&amp;', '&');
  }

  Widget _buildPlainTextWithLinks(String text, TextStyle baseStyle) {
    final matches = _urlRegex.allMatches(text);
    if (matches.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final spans = <InlineSpan>[];
    var lastMatchEnd = 0;

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      final urlText = match.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () async {
          final uri = Uri.tryParse(urlText);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        };
      _recognizers.add(recognizer);

      spans.add(TextSpan(
        text: urlText,
        style: baseStyle.copyWith(
          color: Colors.blue,
          decoration: TextDecoration.underline,
          decorationColor: Colors.blue,
        ),
        recognizer: recognizer,
      ));

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return Text.rich(TextSpan(children: spans), style: baseStyle);
  }
}
