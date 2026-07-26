import 'package:flutter_prerender/src/source_head.dart';
import 'package:test/test.dart';

/// A head shaped like the one `flutter build web` actually emits.
const _builtIndex = '''
<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="description" content="Baked into the build">
  <meta name="theme-color" content="#0175C2">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta property="og:title" content="Baked title">
  <meta name="twitter:card" content="summary">
  <title>coffee</title>
  <link rel="manifest" href="manifest.json">
  <link rel="icon" type="image/png" href="favicon.png">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <link rel="canonical" href="https://example.com/">
  <link rel="stylesheet" href="styles.css">
  <script>window.flutterConfiguration = {};</script>
</head>
<body></body>
</html>
''';

void main() {
  group('SourceHead', () {
    test('keeps the build base href', () {
      // Without it, flutter_bootstrap.js resolves main.dart.js against the
      // deep route it was served from and the app never boots.
      expect(SourceHead.parse(_builtIndex).baseHref, '/');
    });

    test('treats an unsubstituted placeholder as the root', () {
      const template =
          '<html><head><base href="\$FLUTTER_BASE_HREF">'
          '</head><body></body></html>';
      expect(SourceHead.parse(template).baseHref, '/');
    });

    test('reports no base href when the build has none', () {
      expect(SourceHead.parse('<html><head></head></html>').baseHref, isNull);
    });

    test('carries the resources the app needs', () {
      final carried = SourceHead.parse(_builtIndex).carried.join('\n');

      expect(carried, contains('rel="manifest"'));
      expect(carried, contains('favicon.png'));
      expect(carried, contains('apple-touch-icon'));
      expect(carried, contains('theme-color'));
      expect(carried, contains('apple-mobile-web-app-capable'));
      expect(carried, contains('styles.css'));
    });

    test('drops what the generator writes per route', () {
      final carried = SourceHead.parse(_builtIndex).carried.join('\n');

      // These are computed per route, so carrying the build's copies would
      // emit two of each and let the stale one win in some crawlers.
      expect(carried, isNot(contains('<title>')));
      expect(carried, isNot(contains('name="description"')));
      expect(carried, isNot(contains('property="og:')));
      expect(carried, isNot(contains('name="twitter:')));
      expect(carried, isNot(contains('rel="canonical"')));
      expect(carried, isNot(contains('charset')));
      expect(carried, isNot(contains('name="viewport"')));
    });

    test('drops scripts', () {
      // A build's inline service-worker bootstrap re-registers against the
      // wrong scope when it runs from a deep route.
      expect(
        SourceHead.parse(_builtIndex).carried.join('\n'),
        isNot(contains('<script')),
      );
    });

    test('an empty document carries nothing', () {
      expect(SourceHead.parse('').carried, isEmpty);
      expect(SourceHead.parse('').baseHref, isNull);
    });
  });
}
