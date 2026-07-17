@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Locates a Chrome/Chromium executable for the end-to-end test.
///
/// Honours `FLUTTER_PRERENDER_CHROME`, then falls back to a system Chrome.
/// Returns `null` when none is found (the test is skipped).
String? findChrome() {
  final override = Platform.environment['FLUTTER_PRERENDER_CHROME'];
  if (override != null && File(override).existsSync()) return override;
  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

void main() {
  test(
    'prerenders a real Flutter web build into crawlable HTML',
    () async {
      final buildDir = p.join(
        Directory.current.path,
        'example',
        'build',
        'web',
      );
      if (!File(p.join(buildDir, 'index.html')).existsSync()) {
        markTestSkipped(
          'No example build at $buildDir. Run `flutter build web` in example/.',
        );
        return;
      }
      final chrome = findChrome();
      if (chrome == null) {
        markTestSkipped('No Chrome executable found.');
        return;
      }

      final outDir = Directory.systemTemp.createTempSync('fp_e2e_');
      final config = PrerenderConfig(
        buildDir: buildDir,
        outDir: outDir.path,
        baseUrl: 'https://coffee.example.com',
        routes: const [RouteSpec('/')],
        chromeExecutable: chrome,
        waitMs: 4000,
      );
      final server = await StaticServer.start(buildDir);
      final capturer = PuppeteerCapturer(
        executablePath: chrome,
        extraWaitMs: config.waitMs,
      );
      try {
        final engine = PrerenderEngine(config: config, capturer: capturer);
        final result = await engine.run(server.baseUri);

        expect(result.routes, hasLength(1));
        final route = result.routes.single;
        expect(route.nodeCount, greaterThan(0));

        final html = File(route.outputPath).readAsStringSync();
        // The example app renders this heading; it must survive to static HTML.
        expect(html, contains('Quintessential Ethiopian Yirgacheffe'));
        // A real anchor must be recovered from the Link widget.
        expect(html, contains('<a href='));
        // The parity guard should be satisfied for a faithful prerender.
        expect(route.parity?.isSuspicious, isFalse);

        expect(result.sitemapPath, isNotNull);
      } finally {
        await capturer.close();
        await server.close();
        outDir.deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
