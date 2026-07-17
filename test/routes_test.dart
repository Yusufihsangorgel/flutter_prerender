import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:test/test.dart';

void main() {
  group('parseRoutesFile', () {
    test('parses one route per line', () {
      expect(parseRoutesFile('/\n/about\n/beans/kenya'), [
        '/',
        '/about',
        '/beans/kenya',
      ]);
    });

    test('ignores blank lines and comments', () {
      const content = '''
# routes
/

  /about
# trailing comment
''';
      expect(parseRoutesFile(content), ['/', '/about']);
    });

    test('normalises missing leading slash', () {
      expect(parseRoutesFile('about\ncontact'), ['/about', '/contact']);
    });

    test('removes duplicates preserving first-seen order', () {
      expect(parseRoutesFile('/a\n/b\n/a'), ['/a', '/b']);
    });

    test('strips trailing slash except for root', () {
      expect(parseRoutesFile('/\n/about/'), ['/', '/about']);
    });

    test('rejects absolute URLs', () {
      expect(
        () => parseRoutesFile('https://example.com/x'),
        throwsA(isA<ConfigException>()),
      );
    });

    test('rejects paths containing whitespace', () {
      expect(() => normalizeRoute('/a b'), throwsA(isA<ConfigException>()));
    });
  });
}
