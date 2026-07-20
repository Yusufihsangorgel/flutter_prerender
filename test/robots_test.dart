import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:test/test.dart';

void main() {
  group('buildRobotsTxt', () {
    test('allows crawling', () {
      final robots = buildRobotsTxt();
      expect(robots, contains('User-agent: *'));
      expect(robots, contains('Allow: /'));
    });

    test('declares the sitemap when there is one', () {
      final robots = buildRobotsTxt(
        sitemapUrl: 'https://example.com/sitemap.xml',
      );
      expect(robots, contains('Sitemap: https://example.com/sitemap.xml'));
    });

    test('omits the directive when there is no sitemap', () {
      // Pointing at a sitemap that was never written would send crawlers to a
      // 404, which is worse than saying nothing.
      expect(buildRobotsTxt(), isNot(contains('Sitemap:')));
    });

    test('ends with a newline so the last directive is a complete line', () {
      expect(buildRobotsTxt().endsWith('\n'), isTrue);
      expect(
        buildRobotsTxt(sitemapUrl: 'https://x.test/sitemap.xml').endsWith('\n'),
        isTrue,
      );
    });
  });
}
