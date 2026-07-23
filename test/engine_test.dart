import 'dart:io';

import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A capturer that returns canned content per route path.
class _MapCapturer implements PageCapturer {
  _MapCapturer(this.byPath);

  final Map<String, CapturedPage> byPath;

  @override
  Future<CapturedPage> capture(Uri url) async =>
      byPath[url.path] ??
      const CapturedPage(title: '', semanticsHtml: '', renderedText: '');

  @override
  Future<void> close() async {}
}

/// A capturer that returns canned content per route path, and throws
/// [RouteCaptureException] for routes in [failing], mirroring how
/// [PuppeteerCapturer] reacts to a same-origin link that is not a Flutter
/// route (a PDF, an image, and so on).
class _ThrowingCapturer implements PageCapturer {
  _ThrowingCapturer({required this.byPath, required this.failing});

  final Map<String, CapturedPage> byPath;
  final Set<String> failing;

  @override
  Future<CapturedPage> capture(Uri url) async {
    if (failing.contains(url.path)) {
      throw RouteCaptureException(url.path, 'no content was recovered');
    }
    return byPath[url.path] ??
        const CapturedPage(title: '', semanticsHtml: '', renderedText: '');
  }

  @override
  Future<void> close() async {}
}

CapturedPage _page(String semantics, {String? rendered}) => CapturedPage(
  title: 'T',
  semanticsHtml: semantics,
  renderedText: rendered ?? '',
);

void main() {
  late Directory outDir;
  final baseUri = Uri.parse('http://localhost/');

  setUp(() => outDir = Directory.systemTemp.createTempSync('fp_engine_'));
  tearDown(() => outDir.deleteSync(recursive: true));

  test('flags a route that recovers no content', () async {
    final engine = PrerenderEngine(
      config: PrerenderConfig(
        outDir: outDir.path,
        routes: const [RouteSpec('/')],
      ),
      capturer: _MapCapturer({'/': _page('')}),
    );
    final result = await engine.run(baseUri);
    expect(result.hasEmptyRoutes, isTrue);
    expect(result.routes.single.isEmpty, isTrue);
    expect(result.allWarnings.join(), contains('no crawlable content'));
  });

  test(
    'records a route that fails to capture without aborting the run',
    () async {
      final engine = PrerenderEngine(
        config: PrerenderConfig(
          outDir: outDir.path,
          routes: const [RouteSpec('/'), RouteSpec('/assets/resume.pdf')],
        ),
        capturer: _ThrowingCapturer(
          byPath: {
            '/': _page('<flt-semantics-host><h1>Hi</h1></flt-semantics-host>'),
          },
          failing: {'/assets/resume.pdf'},
        ),
      );
      final result = await engine.run(baseUri);
      expect(result.routes.map((r) => r.path), ['/']);
      expect(result.hasFailedRoutes, isTrue);
      expect(result.failedRoutes, hasLength(1));
      expect(result.failedRoutes.single.path, '/assets/resume.pdf');
      expect(result.failedRoutes.single.message, contains('no content'));
    },
  );

  test('warns when two routes produce identical content', () async {
    const semantics =
        '<flt-semantics-host><h1>Same page</h1>'
        '</flt-semantics-host>';
    final engine = PrerenderEngine(
      config: PrerenderConfig(
        outDir: outDir.path,
        routes: const [RouteSpec('/'), RouteSpec('/about')],
      ),
      capturer: _MapCapturer({
        '/': _page(semantics, rendered: 'Same page'),
        '/about': _page(semantics, rendered: 'Same page'),
      }),
    );
    final result = await engine.run(baseUri);
    final about = result.routes.firstWhere((r) => r.path == '/about');
    expect(about.warnings.join(), contains('produced the same content as /'));
  });

  test('warns when sitemap is requested without a base URL', () async {
    final engine = PrerenderEngine(
      config: PrerenderConfig(
        outDir: outDir.path,
        routes: const [RouteSpec('/')],
      ),
      capturer: _MapCapturer({
        '/': _page('<flt-semantics-host><h1>Hi</h1></flt-semantics-host>'),
      }),
    );
    final result = await engine.run(baseUri);
    expect(result.runWarnings.join(), contains('no baseUrl'));
    expect(result.sitemapPath, isNull);
  });

  test('warns when a relative app script meets a nested route', () async {
    final engine = PrerenderEngine(
      config: PrerenderConfig(
        outDir: outDir.path,
        appScriptSrc: 'flutter_bootstrap.js',
        routes: const [RouteSpec('/beans/kenya')],
      ),
      capturer: _MapCapturer({
        '/beans/kenya': _page(
          '<flt-semantics-host><h1>Kenya</h1></flt-semantics-host>',
        ),
      }),
    );
    final result = await engine.run(baseUri);
    expect(result.runWarnings.join(), contains('may 404 on deep routes'));
  });

  test('does not warn about the default absolute app script', () async {
    final engine = PrerenderEngine(
      config: PrerenderConfig(
        outDir: outDir.path,
        routes: const [RouteSpec('/beans/kenya')],
      ),
      capturer: _MapCapturer({
        '/beans/kenya': _page(
          '<flt-semantics-host><h1>Kenya</h1></flt-semantics-host>',
        ),
      }),
    );
    final result = await engine.run(baseUri);
    expect(result.runWarnings.join(), isNot(contains('404')));
    final html = File(
      p.join(outDir.path, 'beans', 'kenya', 'index.html'),
    ).readAsStringSync();
    expect(html, contains('src="/flutter_bootstrap.js"'));
  });
}
