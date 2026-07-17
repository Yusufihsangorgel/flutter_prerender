/// A single `<url>` entry in a sitemap.
class SitemapEntry {
  /// Creates a sitemap entry for the absolute URL [loc].
  const SitemapEntry(this.loc, {this.lastmod, this.changefreq, this.priority});

  /// The absolute URL of the page.
  final String loc;

  /// The date the page was last modified, serialised as `YYYY-MM-DD`.
  final DateTime? lastmod;

  /// How frequently the page is likely to change (for example `weekly`).
  final String? changefreq;

  /// The relative priority of this URL in the range 0.0..1.0.
  final double? priority;
}

/// Builds a `sitemap.xml` document from [entries].
///
/// The output conforms to the sitemaps.org 0.9 schema. URLs and dates are
/// XML-escaped, so callers may pass URLs containing `&` or other reserved
/// characters safely.
String buildSitemap(Iterable<SitemapEntry> entries) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
  for (final entry in entries) {
    buffer.writeln('  <url>');
    buffer.writeln('    <loc>${_escapeXml(entry.loc)}</loc>');
    if (entry.lastmod != null) {
      buffer.writeln('    <lastmod>${_formatDate(entry.lastmod!)}</lastmod>');
    }
    if (entry.changefreq != null) {
      buffer.writeln(
        '    <changefreq>${_escapeXml(entry.changefreq!)}</changefreq>',
      );
    }
    if (entry.priority != null) {
      buffer.writeln(
        '    <priority>${entry.priority!.toStringAsFixed(1)}</priority>',
      );
    }
    buffer.writeln('  </url>');
  }
  buffer.writeln('</urlset>');
  return buffer.toString();
}

/// Joins a site [baseUrl] and a route [path] into a single absolute URL,
/// collapsing the slash between them.
String joinUrl(String baseUrl, String path) {
  final base = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  if (path == '/' || path.isEmpty) return '$base/';
  final suffix = path.startsWith('/') ? path : '/$path';
  return '$base$suffix';
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
