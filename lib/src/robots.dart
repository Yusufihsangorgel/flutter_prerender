/// Builds a `robots.txt` that allows crawling and, when [sitemapUrl] is given,
/// points crawlers at the sitemap.
///
/// A sitemap nothing links to is half the job: crawlers do probe
/// `/sitemap.xml` by convention, but the `Sitemap:` directive is the
/// documented way to declare it and is what non-Google crawlers and webmaster
/// tools read.
String buildRobotsTxt({String? sitemapUrl}) {
  final buffer = StringBuffer()
    ..writeln('User-agent: *')
    ..writeln('Allow: /');
  if (sitemapUrl != null) {
    buffer
      ..writeln()
      ..writeln('Sitemap: $sitemapUrl');
  }
  return buffer.toString();
}
