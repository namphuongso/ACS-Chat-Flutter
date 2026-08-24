import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class LinkPreviewData {
  const LinkPreviewData({
    required this.url,
    required this.title,
    this.description,
    this.imageUrl,
    required this.domain,
  });

  final String url;
  final String title;
  final String? description;
  final String? imageUrl;
  final String domain;

  Map<String, dynamic> toJson() => {
        'type': 'link',
        'url': url,
        'title': title,
        if (description != null && description!.trim().isNotEmpty)
          'description': description!.trim(),
        if (imageUrl != null && imageUrl!.trim().isNotEmpty)
          'imageUrl': imageUrl!.trim(),
        'domain': domain,
      };
}

class LinkPreviewFetcher {
  static final _cache = <String, LinkPreviewData>{};

  static Future<LinkPreviewData> fetch(String rawUrl) async {
    final cleanUrl = rawUrl.trim();
    if (_cache.containsKey(cleanUrl)) {
      return _cache[cleanUrl]!;
    }

    final uri = Uri.tryParse(cleanUrl);
    final domain = uri?.host ?? '';
    final defaultData = LinkPreviewData(
      url: cleanUrl,
      title: domain.isNotEmpty ? domain : cleanUrl,
      domain: domain,
    );

    if (uri == null || !uri.hasScheme) {
      return defaultData;
    }

    try {
      final response = await http.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return defaultData;
      }

      final doc = html_parser.parse(response.body);

      String? title;
      String? description;
      String? imageUrl;

      for (final meta in doc.getElementsByTagName('meta')) {
        final property = meta.attributes['property']?.toLowerCase() ??
            meta.attributes['name']?.toLowerCase() ??
            '';
        final content = meta.attributes['content']?.trim();

        if (content == null || content.isEmpty) continue;

        if (property == 'og:title' || property == 'twitter:title') {
          title ??= content;
        } else if (property == 'og:description' ||
            property == 'twitter:description' ||
            property == 'description') {
          description ??= content;
        } else if (property == 'og:image' ||
            property == 'og:image:url' ||
            property == 'twitter:image') {
          imageUrl ??= content;
        }
      }

      if (title == null || title.isEmpty) {
        final titleElement = doc.querySelector('title');
        if (titleElement != null && titleElement.text.trim().isNotEmpty) {
          title = titleElement.text.trim();
        }
      }

      if (imageUrl != null && imageUrl.isNotEmpty) {
        final imgUri = Uri.tryParse(imageUrl);
        if (imgUri != null && !imgUri.hasScheme) {
          imageUrl = uri.resolveUri(imgUri).toString();
        }
      }

      final result = LinkPreviewData(
        url: cleanUrl,
        title: title ?? (domain.isNotEmpty ? domain : cleanUrl),
        description: description,
        imageUrl: imageUrl,
        domain: domain,
      );

      if (_cache.length >= 100) {
        _cache.remove(_cache.keys.first);
      }
      _cache[cleanUrl] = result;
      return result;
    } catch (_) {
      return defaultData;
    }
  }
}
