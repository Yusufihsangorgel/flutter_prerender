import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:test/test.dart';

void main() {
  group('joinUrl', () {
    test('joins base and path collapsing the slash', () {
      expect(joinUrl('https://x.com', '/about'), 'https://x.com/about');
      expect(joinUrl('https://x.com/', '/about'), 'https://x.com/about');
      expect(joinUrl('https://x.com/', 'about'), 'https://x.com/about');
    });

    test('maps root to a trailing slash', () {
      expect(joinUrl('https://x.com', '/'), 'https://x.com/');
    });
  });

  group('buildSitemap', () {
    test('emits a valid urlset with each loc', () {
      final xml = buildSitemap(const [
        SitemapEntry('https://x.com/'),
        SitemapEntry('https://x.com/about'),
      ]);
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(
        xml,
        contains(
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
        ),
      );
      expect(xml, contains('<loc>https://x.com/</loc>'));
      expect(xml, contains('<loc>https://x.com/about</loc>'));
      expect(xml.trim(), endsWith('</urlset>'));
    });

    test('escapes reserved characters in URLs', () {
      final xml = buildSitemap(const [
        SitemapEntry('https://x.com/search?a=1&b=2'),
      ]);
      expect(xml, contains('<loc>https://x.com/search?a=1&amp;b=2</loc>'));
      expect(xml, isNot(contains('a=1&b=2')));
    });

    test('formats lastmod, changefreq and priority', () {
      final xml = buildSitemap([
        SitemapEntry(
          'https://x.com/',
          lastmod: DateTime(2026, 7, 5),
          changefreq: 'weekly',
          priority: 0.8,
        ),
      ]);
      expect(xml, contains('<lastmod>2026-07-05</lastmod>'));
      expect(xml, contains('<changefreq>weekly</changefreq>'));
      expect(xml, contains('<priority>0.8</priority>'));
    });

    test('empty entries still produce a well-formed document', () {
      final xml = buildSitemap(const []);
      expect(xml, contains('<urlset'));
      expect(xml, contains('</urlset>'));
    });
  });
}
