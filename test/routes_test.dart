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

    test('rejects a parent-directory escape', () {
      expect(
        () => normalizeRoute('../etc/passwd'),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => normalizeRoute('/../secret'),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => normalizeRoute('/a/../../b'),
        throwsA(isA<ConfigException>()),
      );
    });

    test('rejects a leading double slash that would be an absolute path', () {
      expect(
        () => normalizeRoute('//etc/passwd'),
        throwsA(isA<ConfigException>()),
      );
    });

    test('keeps a dotted segment that is not a traversal', () {
      expect(normalizeRoute('/..foo'), '/..foo');
      expect(normalizeRoute('/a.b/c'), '/a.b/c');
    });
  });

  group('sameOriginRoute', () {
    test('skips a discovered relative traversal link instead of throwing', () {
      expect(sameOriginRoute('../../etc/passwd'), isNull);
      expect(sameOriginRoute('../secret'), isNull);
    });

    test('normalises a safe absolute link and resolves ordinary links', () {
      // A leading `..` on an absolute path cannot climb above root, and Uri
      // collapses it, so this stays inside the site rather than being skipped.
      expect(sameOriginRoute('/../secret'), '/secret');
      expect(sameOriginRoute('about'), '/about');
      expect(sameOriginRoute('/beans/kenya?q=1#top'), '/beans/kenya');
    });
  });
}
