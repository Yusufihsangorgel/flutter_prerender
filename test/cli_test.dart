import 'dart:io';

import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A capturer that returns canned content, so the full pipeline can run
/// without a real browser.
class _FakeCapturer implements PageCapturer {
  _FakeCapturer({required this.semanticsHtml, required this.renderedText});

  final String semanticsHtml;
  final String renderedText;
  final String title = 'Fake Title';

  @override
  Future<CapturedPage> capture(Uri url) async => CapturedPage(
    title: title,
    semanticsHtml: semanticsHtml,
    renderedText: renderedText,
  );

  @override
  Future<void> close() async {}
}

/// A capturer that throws [RouteCaptureException] for routes in [failing]
/// and returns canned content for everything else, so a run with one bad
/// same-origin link can be exercised end to end.
class _PartialFailureCapturer implements PageCapturer {
  _PartialFailureCapturer({required this.failing});

  final Set<String> failing;

  @override
  Future<CapturedPage> capture(Uri url) async {
    if (failing.contains(url.path)) {
      throw RouteCaptureException(url.path, 'no content was recovered');
    }
    return const CapturedPage(
      title: 'Fake Title',
      semanticsHtml: '<flt-semantics-host><h1>Coffee</h1></flt-semantics-host>',
      renderedText: 'Coffee',
    );
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('--help prints usage and exits 0', () async {
    final out = StringBuffer();
    final code = await runCli(['--help'], out: out, err: StringBuffer());
    expect(code, 0);
    expect(out.toString(), contains('Usage: flutter_prerender'));
  });

  test('--version prints the version and exits 0', () async {
    final out = StringBuffer();
    final code = await runCli(['--version'], out: out, err: StringBuffer());
    expect(code, 0);
    expect(out.toString(), contains('flutter_prerender $packageVersion'));
  });

  test('an unknown flag exits 64', () async {
    final code = await runCli(
      ['--nope'],
      out: StringBuffer(),
      err: StringBuffer(),
    );
    expect(code, 64);
  });

  test('an invalid numeric flag is rejected, not ignored', () async {
    final err = StringBuffer();
    final code = await runCli(
      ['--build-dir', 'build/web', '--port', 'abc'],
      out: StringBuffer(),
      err: err,
    );
    expect(code, 1);
    expect(err.toString(), contains('--port must be an integer'));
  });

  test('no routes exits 1 with an explanatory error', () async {
    final err = StringBuffer();
    final code = await runCli(
      ['--build-dir', 'build/web'],
      out: StringBuffer(),
      err: err,
    );
    expect(code, 1);
    expect(err.toString(), contains('No routes'));
  });

  group('with a temp workspace', () {
    late Directory dir;
    late String buildDir;
    late String outDir;
    late String routesFile;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fp_cli_');
      buildDir = p.join(dir.path, 'web');
      outDir = p.join(dir.path, 'pre');
      routesFile = p.join(dir.path, 'routes.txt');
      Directory(buildDir).createSync(recursive: true);
      File(p.join(buildDir, 'index.html')).writeAsStringSync('<html></html>');
      File(routesFile).writeAsStringSync('/\n/about\n');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('dry run prints the plan and exits 0', () async {
      final out = StringBuffer();
      final code = await runCli(
        [
          '--dry-run',
          '--build-dir',
          buildDir,
          '--routes',
          routesFile,
          '--base-url',
          'https://x.com',
        ],
        out: out,
        err: StringBuffer(),
      );
      expect(code, 0);
      expect(out.toString(), contains('(dry run)'));
      expect(out.toString(), contains('/about'));
    });

    test('missing build directory exits 1', () async {
      final err = StringBuffer();
      final code = await runCli(
        [
          '--build-dir',
          p.join(dir.path, 'does-not-exist'),
          '--routes',
          routesFile,
        ],
        out: StringBuffer(),
        err: err,
      );
      expect(code, 1);
      expect(err.toString(), contains('No Flutter web build'));
    });

    test('full run writes HTML, meta and a sitemap', () async {
      final out = StringBuffer();
      final code = await runCli(
        [
          '--build-dir',
          buildDir,
          '--routes',
          routesFile,
          '--out',
          outDir,
          '--base-url',
          'https://x.com',
        ],
        out: out,
        err: StringBuffer(),
        capturerFactory: (_) => _FakeCapturer(
          semanticsHtml:
              '<flt-semantics-host><h1>Coffee</h1>'
              '<flt-semantics><span>Fresh beans daily</span></flt-semantics>'
              '</flt-semantics-host>',
          renderedText: 'Coffee Fresh beans daily',
        ),
      );
      expect(code, 0);

      final home = File(p.join(outDir, 'index.html'));
      final about = File(p.join(outDir, 'about', 'index.html'));
      final sitemap = File(p.join(outDir, 'sitemap.xml'));
      expect(home.existsSync(), isTrue);
      expect(about.existsSync(), isTrue);
      expect(sitemap.existsSync(), isTrue);

      final homeHtml = home.readAsStringSync();
      expect(homeHtml, contains('<h1>Coffee</h1>'));
      expect(homeHtml, contains('<p>Fresh beans daily</p>'));
      expect(
        homeHtml,
        contains('<link rel="canonical" href="https://x.com/">'),
      );

      final sitemapXml = sitemap.readAsStringSync();
      expect(sitemapXml, contains('<loc>https://x.com/</loc>'));
      expect(sitemapXml, contains('<loc>https://x.com/about</loc>'));
    });

    test('a route that fails to capture does not abort the run', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        [
          '--build-dir',
          buildDir,
          '--routes',
          routesFile,
          '--out',
          outDir,
          '--base-url',
          'https://x.com',
        ],
        out: out,
        err: err,
        capturerFactory: (_) => _PartialFailureCapturer(failing: {'/about'}),
      );
      expect(code, 0);

      final home = File(p.join(outDir, 'index.html'));
      expect(home.existsSync(), isTrue);
      final about = File(p.join(outDir, 'about', 'index.html'));
      expect(about.existsSync(), isFalse);

      final sitemap = File(p.join(outDir, 'sitemap.xml'));
      expect(sitemap.existsSync(), isTrue);
      expect(sitemap.readAsStringSync(), isNot(contains('/about')));

      expect(out.toString(), contains('[failed: no content was recovered]'));
      expect(err.toString(), contains('/about: failed to capture'));
    });

    test('--fail-on-empty exits 3 when a route fails to capture', () async {
      final err = StringBuffer();
      final code = await runCli(
        [
          '--build-dir',
          buildDir,
          '--routes',
          routesFile,
          '--out',
          outDir,
          '--fail-on-empty',
        ],
        out: StringBuffer(),
        err: err,
        capturerFactory: (_) => _PartialFailureCapturer(failing: {'/about'}),
      );
      expect(code, 3);
      expect(err.toString(), contains('/about: failed to capture'));
    });

    test('--fail-on-empty exits 3 and labels empty routes', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        [
          '--build-dir',
          buildDir,
          '--routes',
          routesFile,
          '--out',
          outDir,
          '--fail-on-empty',
        ],
        out: out,
        err: err,
        capturerFactory: (_) =>
            _FakeCapturer(semanticsHtml: '', renderedText: ''),
      );
      expect(code, 3);
      expect(out.toString(), contains('[empty: no content recovered]'));
      expect(err.toString(), contains('no crawlable content'));
    });

    test('--fail-on-parity exits 2 when content is injected', () async {
      final code = await runCli(
        [
          '--build-dir',
          buildDir,
          '--routes',
          routesFile,
          '--out',
          outDir,
          '--fail-on-parity',
        ],
        out: StringBuffer(),
        err: StringBuffer(),
        capturerFactory: (_) => _FakeCapturer(
          // The recovered content contains words the app never rendered.
          semanticsHtml:
              '<flt-semantics-host><h1>Injected Keywords Everywhere</h1>'
              '</flt-semantics-host>',
          renderedText: 'nothing in common here',
        ),
      );
      expect(code, 2);
    });
  });
}
