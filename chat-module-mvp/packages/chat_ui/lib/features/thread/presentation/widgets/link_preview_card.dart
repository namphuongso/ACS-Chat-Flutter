import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/link_preview_fetcher.dart';

class LinkPreviewCard extends StatefulWidget {
  const LinkPreviewCard({
    super.key,
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.domain,
    required this.textColor,
  });

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? domain;
  final Color textColor;

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  LinkPreviewData? _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.title != null &&
        widget.title!.isNotEmpty &&
        widget.title != widget.domain &&
        widget.title != widget.url) {
      _data = LinkPreviewData(
        url: widget.url,
        title: widget.title!,
        description: widget.description,
        imageUrl: widget.imageUrl,
        domain: widget.domain ?? Uri.tryParse(widget.url)?.host ?? '',
      );
    } else {
      _fetchData();
    }
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    final data = await LinkPreviewFetcher.fetch(widget.url);
    if (mounted) {
      setState(() {
        _data = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _data?.title ??
        widget.title ??
        (Uri.tryParse(widget.url)?.host ?? widget.url);
    final description = _data?.description ?? widget.description;
    final imageUrl = _data?.imageUrl ?? widget.imageUrl;
    final domain =
        _data?.domain ?? widget.domain ?? (Uri.tryParse(widget.url)?.host ?? '');

    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(widget.url);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 4),
        decoration: BoxDecoration(
          color: widget.textColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.textColor.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                width: double.infinity,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loading) ...[
                    Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          domain,
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.textColor.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    if (domain.isNotEmpty)
                      Text(
                        domain.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: widget.textColor.withValues(alpha: 0.6),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: widget.textColor,
                      ),
                    ),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.textColor.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
