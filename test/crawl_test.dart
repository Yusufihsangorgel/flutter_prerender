import 'dart:io';

import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:test/test.dart';

/// A capturer that returns canned semantics per route path.
class _MapCapturer implements PageCapturer {
  _MapCapturer(this.byPath);

  final Map<String, String> byPath;

  @override
  Future<CapturedPage> capture(Uri url) async => CapturedPage(
    title: 'T',
    semanticsHtml: byPath[url.path] ?? '',
    renderedText: '',
  );

  @override
  Future<void> close() async {}
}

String _links(List<String> hrefs) =>
    '<flt-semantics-host><h1>Page</h1>'
    '${hrefs.map((h) => '<a href="$h">link</a>').join()}'
    '</flt-semantics-host>';

void main() {
  group('sameOriginRoute', () {
    test(
      'keeps relative and root-relative links, dropping query and fragment',
      () {
        expect(sameOriginRoute('/about'), '/about');
        expect(sameOriginRoute('beans/kenya'), '/beans/kenya');
        expect(sameOriginRoute('/x?y=1#z'), '/x');
      },
    );

    test('drops off-site, non-page, and empty links', () {
      expect(sameOriginRoute('https://external.com/x'), isNull);
      expect(sameOriginRoute('mailto:hi@example.com'), isNull);
      expect(sameOriginRoute('tel:+15551234'), isNull);
      expect(sameOriginRoute('#section'), isNull);
      expect(sameOriginRoute('//cdn.example.com/a'), isNull);
      expect(sameOriginRoute('   '), isNull);
    });

    test('keeps an absolute URL only when its origin matches', () {
      const origin = 'https://example.com';
      expect(
        sameOriginRoute('https://example.com/about', origin: origin),
        '/about',
      );
      expect(
        sameOriginRoute('https://other.com/about', origin: origin),
        isNull,
      );
      // No origin to compare against: absolute URLs cannot be confirmed.
      expect(sameOriginRoute('https://example.com/about'), isNull);
    });
  });

  group('discoverRoutes', () {
    test('enqueues only new same-origin paths, de-duplicated', () {
      final routes = discoverRoutes(
        [
          '/',
          '/about',
          'beans/kenya',
          '/about',
          'https://example.com/contact',
          'https://external.com/x',
          'mailto:a@b.com',
          '#top',
        ],
        known: {'/'},
        limit: 100,
        origin: 'https://example.com',
      );
      expect(routes, ['/about', '/beans/kenya', '/contact']);
    });

    test('bounds the result at limit', () {
      final routes = discoverRoutes(
        ['/a', '/b', '/c', '/d'],
        known: {'/'},
        limit: 2,
      );
      expect(routes, ['/a', '/b']);
    });

    test('returns nothing when there is no room left', () {
      final routes = discoverRoutes(['/a'], known: {'/'}, limit: 0);
      expect(routes, isEmpty);
    });
  });

  group('PrerenderEngine crawl', () {
    late Directory outDir;
    final baseUri = Uri.parse('http://localhost/');

    setUp(() => outDir = Directory.systemTemp.createTempSync('fp_crawl_'));
    tearDown(() => outDir.deleteSync(recursive: true));

    test('follows in-page links from the seed', () async {
      final engine = PrerenderEngine(
        config: PrerenderConfig(outDir: outDir.path, crawl: true),
        capturer: _MapCapturer({
          '/': _links(['/about', '/beans', 'https://external.com/x']),
          '/about': _links(['/']),
          '/beans': _links(['/beans/kenya']),
          '/beans/kenya': _links([]),
        }),
      );
      final result = await engine.run(baseUri);
      final paths = result.routes.map((r) => r.path).toSet();
      expect(paths, {'/', '/about', '/beans', '/beans/kenya'});
    });

    test('does not discover routes when crawl is off', () async {
      final engine = PrerenderEngine(
        config: PrerenderConfig(
          outDir: outDir.path,
          routes: const [RouteSpec('/')],
        ),
        capturer: _MapCapturer({
          '/': _links(['/about']),
        }),
      );
      final result = await engine.run(baseUri);
      expect(result.routes.map((r) => r.path), ['/']);
    });

    test('stops at maxPages', () async {
      final engine = PrerenderEngine(
        config: PrerenderConfig(outDir: outDir.path, crawl: true, maxPages: 2),
        capturer: _MapCapturer({
          '/': _links(['/a', '/b', '/c']),
          '/a': _links([]),
          '/b': _links([]),
          '/c': _links([]),
        }),
      );
      final result = await engine.run(baseUri);
      expect(result.routes, hasLength(2));
    });
  });
}
