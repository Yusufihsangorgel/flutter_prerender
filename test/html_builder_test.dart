import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:test/test.dart';

void main() {
  const builder = HtmlBuilder();

  test('renders headings, paragraphs, links and images', () {
    final html = builder.build(
      nodes: [
        HeadingContent('Title', level: 1),
        const ParagraphContent('Body text'),
        const LinkContent(href: '/next', text: 'Next'),
        const ImageContent('A photo'),
      ],
      meta: const RouteMeta(),
    );
    expect(html, contains('<h1>Title</h1>'));
    expect(html, contains('<p>Body text</p>'));
    expect(html, contains('<a href="/next">Next</a>'));
    expect(html, contains('<img alt="A photo">'));
  });

  test('escapes HTML-special characters in text and attributes', () {
    final html = builder.build(
      nodes: const [
        ParagraphContent('Tom & Jerry <script>'),
        LinkContent(href: '/a?x=1&y=2', text: 'A & B'),
      ],
      meta: const RouteMeta(),
    );
    expect(html, contains('<p>Tom &amp; Jerry &lt;script&gt;</p>'));
    expect(html, contains('<a href="/a?x=1&amp;y=2">A &amp; B</a>'));
    // The literal "<script>" from the paragraph text must be escaped, not
    // emitted as a real element inside the content container.
    expect(html, isNot(contains('Jerry <script>')));
  });

  test('writes title, description and canonical', () {
    final html = builder.build(
      nodes: const [],
      meta: const RouteMeta(
        title: 'Coffee',
        description: 'Fresh beans',
        canonical: 'https://example.com/',
      ),
    );
    expect(html, contains('<title>Coffee</title>'));
    expect(html, contains('<meta name="description" content="Fresh beans">'));
    expect(
      html,
      contains('<link rel="canonical" href="https://example.com/">'),
    );
  });

  test('writes Open Graph and Twitter tags', () {
    final html = builder.build(
      nodes: const [],
      meta: const RouteMeta(
        title: 'Coffee',
        description: 'Fresh beans',
        image: 'https://example.com/og.png',
      ),
      pageUrl: 'https://example.com/',
    );
    expect(html, contains('<meta property="og:title" content="Coffee">'));
    expect(
      html,
      contains('<meta property="og:url" content="https://example.com/">'),
    );
    expect(
      html,
      contains(
        '<meta property="og:image" content="https://example.com/og.png">',
      ),
    );
    expect(
      html,
      contains('<meta name="twitter:card" content="summary_large_image">'),
    );
  });

  test('uses summary card when no image is provided', () {
    final html = builder.build(
      nodes: const [],
      meta: const RouteMeta(title: 'X'),
    );
    expect(html, contains('<meta name="twitter:card" content="summary">'));
  });

  test('emits JSON-LD and neutralises embedded </script>', () {
    final html = builder.build(
      nodes: const [],
      meta: const RouteMeta(
        jsonLd: {
          '@context': 'https://schema.org',
          '@type': 'Organization',
          'name': 'Danger </script>',
        },
      ),
    );
    expect(html, contains('<script type="application/ld+json">'));
    expect(html, contains('"@type": "Organization"'));
    // The literal closing tag must be escaped so it cannot break out.
    expect(html, isNot(contains('Danger </script>')));
    expect(html, contains(r'</script>'));
  });

  test('includes the Flutter bootstrap script by default', () {
    final html = builder.build(nodes: const [], meta: const RouteMeta());
    expect(
      html,
      contains('<script src="flutter_bootstrap.js" async></script>'),
    );
    expect(html, contains('id="flutter-prerender-content"'));
  });

  test('omits the app script when disabled', () {
    const noScript = HtmlBuilder(includeAppScript: false);
    final html = noScript.build(nodes: const [], meta: const RouteMeta());
    expect(html, isNot(contains('flutter_bootstrap.js')));
  });

  test('honours lang and base href', () {
    const custom = HtmlBuilder(lang: 'de', baseHref: '/app/');
    final html = custom.build(nodes: const [], meta: const RouteMeta());
    expect(html, contains('<html lang="de">'));
    expect(html, contains('<base href="/app/">'));
  });

  test('falls back to captured title when meta has none', () {
    final html = builder.build(
      nodes: const [],
      meta: const RouteMeta(),
      fallbackTitle: 'Captured Title',
    );
    expect(html, contains('<title>Captured Title</title>'));
  });

  test('clamps out-of-range heading levels', () {
    final html = builder.build(
      nodes: [HeadingContent('Deep', level: 9)],
      meta: const RouteMeta(),
    );
    expect(html, contains('<h6>Deep</h6>'));
  });
}
