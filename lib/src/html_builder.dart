import 'dart:convert';

import 'content_node.dart';
import 'route_meta.dart';

/// Serialises recovered [ContentNode]s and [RouteMeta] into a complete, static,
/// crawlable HTML document.
///
/// The generated page contains real, visible markup (`<h1>`, `<p>`, `<a>`,
/// `<img alt>`) rather than opacity-zero text, plus a `<head>` populated with
/// title, description, Open Graph, Twitter Card and optional JSON-LD tags.
///
/// When [includeAppScript] is `true` the page also loads the original Flutter
/// app via [appScriptSrc]; JavaScript-capable visitors therefore receive the
/// full application, while crawlers read the static content. This is the
/// dynamic-rendering pattern that Google documents as an accepted way to make
/// canvas/WebGL content indexable. It is not cloaking, provided the static
/// text matches what the app renders (see the content-parity guard).
final class HtmlBuilder {
  /// Creates an HTML builder.
  const HtmlBuilder({
    this.lang = 'en',
    this.includeAppScript = true,
    this.appScriptSrc = '/flutter_bootstrap.js',
    this.baseHref,
  });

  /// The value of the document's `lang` attribute.
  final String lang;

  /// Whether to include a `<script>` that boots the original Flutter app.
  final bool includeAppScript;

  /// The `src` of the Flutter bootstrap script, resolved relative to the page.
  final String appScriptSrc;

  /// An optional `<base href>` written into the document head.
  final String? baseHref;

  /// Builds the HTML document for one route.
  ///
  /// [nodes] is the recovered content in document order. [meta] provides SEO
  /// metadata (already merged with document defaults). [fallbackTitle] is used
  /// when [meta] has no title. [pageUrl] is the absolute URL of the route,
  /// used for `og:url` and as the canonical URL when [meta] does not set one.
  String build({
    required List<ContentNode> nodes,
    required RouteMeta meta,
    String? fallbackTitle,
    String? pageUrl,
  }) {
    final title = meta.title ?? fallbackTitle ?? '';
    final canonical = meta.canonical ?? pageUrl;
    final buffer = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="${_attr(lang)}">')
      ..writeln('<head>')
      ..writeln('  <meta charset="utf-8">')
      ..writeln(
        '  <meta name="viewport" content="width=device-width, '
        'initial-scale=1">',
      );

    if (baseHref != null) {
      buffer.writeln('  <base href="${_attr(baseHref!)}">');
    }
    if (title.isNotEmpty) {
      buffer.writeln('  <title>${_text(title)}</title>');
    }
    if (meta.description != null) {
      buffer.writeln(
        '  <meta name="description" content="${_attr(meta.description!)}">',
      );
    }
    if (canonical != null) {
      buffer.writeln('  <link rel="canonical" href="${_attr(canonical)}">');
    }

    _writeOpenGraph(buffer, meta, title, pageUrl);
    _writeTwitter(buffer, meta, title);
    _writeJsonLd(buffer, meta.jsonLd);

    buffer
      ..writeln('</head>')
      ..writeln('<body>')
      ..writeln('  <div id="flutter-prerender-content">');
    for (final node in nodes) {
      buffer.writeln('    ${_renderNode(node)}');
    }
    buffer.writeln('  </div>');

    if (includeAppScript) {
      _writeAppScript(buffer);
    }

    buffer
      ..writeln('</body>')
      ..writeln('</html>');
    return buffer.toString();
  }

  void _writeOpenGraph(
    StringBuffer buffer,
    RouteMeta meta,
    String title,
    String? pageUrl,
  ) {
    buffer.writeln(
      '  <meta property="og:type" content="${_attr(meta.ogType ?? 'website')}">',
    );
    if (title.isNotEmpty) {
      buffer.writeln('  <meta property="og:title" content="${_attr(title)}">');
    }
    if (meta.description != null) {
      buffer.writeln(
        '  <meta property="og:description" '
        'content="${_attr(meta.description!)}">',
      );
    }
    if (pageUrl != null) {
      buffer.writeln('  <meta property="og:url" content="${_attr(pageUrl)}">');
    }
    if (meta.image != null) {
      buffer.writeln(
        '  <meta property="og:image" content="${_attr(meta.image!)}">',
      );
    }
  }

  void _writeTwitter(StringBuffer buffer, RouteMeta meta, String title) {
    final card = meta.image != null ? 'summary_large_image' : 'summary';
    buffer.writeln('  <meta name="twitter:card" content="$card">');
    if (title.isNotEmpty) {
      buffer.writeln('  <meta name="twitter:title" content="${_attr(title)}">');
    }
    if (meta.description != null) {
      buffer.writeln(
        '  <meta name="twitter:description" '
        'content="${_attr(meta.description!)}">',
      );
    }
    if (meta.image != null) {
      buffer.writeln(
        '  <meta name="twitter:image" content="${_attr(meta.image!)}">',
      );
    }
  }

  void _writeJsonLd(StringBuffer buffer, Map<String, Object?>? jsonLd) {
    if (jsonLd == null || jsonLd.isEmpty) return;
    // Escape "<" so a value cannot terminate the surrounding <script> element.
    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(jsonLd).replaceAll('<', '\\u003c');
    buffer
      ..writeln('  <script type="application/ld+json">')
      ..writeln(encoded)
      ..writeln('  </script>');
  }

  void _writeAppScript(StringBuffer buffer) {
    buffer
      ..writeln('  <script src="${_attr(appScriptSrc)}" async></script>')
      ..writeln('  <script>')
      ..writeln(
        '    // Remove the prerendered fallback once the Flutter app boots so',
      )
      ..writeln(
        '    // JavaScript visitors see the live app, not the static snapshot.',
      )
      ..writeln('    (function () {')
      ..writeln(
        "      var content = "
        "document.getElementById('flutter-prerender-content');",
      )
      ..writeln('      if (!content) return;')
      ..writeln('      var observer = new MutationObserver(function () {')
      ..writeln(
        "        if (document.querySelector('flt-glass-pane, flutter-view')) {",
      )
      ..writeln('          content.remove();')
      ..writeln('          observer.disconnect();')
      ..writeln('        }')
      ..writeln('      });')
      ..writeln(
        '      observer.observe(document.body, '
        '{ childList: true, subtree: true });',
      )
      ..writeln('    })();')
      ..writeln('  </script>');
  }

  String _renderNode(ContentNode node) {
    return switch (node) {
      HeadingContent(:final level, :final text) =>
        '<h$level>${_text(text)}</h$level>',
      ParagraphContent(:final text) => '<p>${_text(text)}</p>',
      LinkContent(:final href, :final text) =>
        '<a href="${_attr(href.isEmpty ? '#' : href)}">${_text(text)}</a>',
      ImageContent(:final alt) => '<img alt="${_attr(alt)}">',
    };
  }

  static String _text(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _attr(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
