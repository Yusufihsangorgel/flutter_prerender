import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:test/test.dart';

void main() {
  final extractor = SemanticsExtractor();

  test('empty input yields no nodes', () {
    expect(extractor.extract(''), isEmpty);
    expect(extractor.extract('   '), isEmpty);
  });

  test('stock spans become paragraphs in document order', () {
    const html = '''
<flt-semantics-host>
  <flt-semantics>
    <flt-semantics><span>Zebrafish Coffee Roasters</span></flt-semantics>
    <flt-semantics><span>Quintessential Ethiopian Yirgacheffe</span></flt-semantics>
  </flt-semantics>
</flt-semantics-host>''';
    expect(extractor.extract(html), const [
      ParagraphContent('Zebrafish Coffee Roasters'),
      ParagraphContent('Quintessential Ethiopian Yirgacheffe'),
    ]);
  });

  test('real <h1> becomes a level-1 heading', () {
    final nodes = extractor.extract(
      '<flt-semantics-host><h1>Hello</h1></flt-semantics-host>',
    );
    expect(nodes, [HeadingContent('Hello', level: 1)]);
  });

  test('role="heading" with aria-level becomes the right level', () {
    const html =
        '<flt-semantics-host><flt-semantics role="heading" aria-level="3">'
        '<span>Section</span></flt-semantics></flt-semantics-host>';
    expect(extractor.extract(html), [HeadingContent('Section', level: 3)]);
  });

  test('anchor with href becomes a link', () {
    const html =
        '<flt-semantics-host><a href="/beans/kenya">Read more</a>'
        '</flt-semantics-host>';
    expect(extractor.extract(html), const [
      LinkContent(href: '/beans/kenya', text: 'Read more'),
    ]);
  });

  test('role="link" wrapping an anchor recovers the href', () {
    const html =
        '<flt-semantics-host><flt-semantics role="link">'
        '<a href="/x">Go</a></flt-semantics></flt-semantics-host>';
    expect(extractor.extract(html), const [
      LinkContent(href: '/x', text: 'Go'),
    ]);
  });

  test('role="img" with aria-label becomes an image', () {
    const html =
        '<flt-semantics-host><flt-semantics role="img" '
        'aria-label="A roasted batch of beans"></flt-semantics>'
        '</flt-semantics-host>';
    expect(extractor.extract(html), const [
      ImageContent('A roasted batch of beans'),
    ]);
  });

  test('real <img alt> becomes an image', () {
    const html =
        '<flt-semantics-host><img alt="Kenya beans"></flt-semantics-host>';
    expect(extractor.extract(html), const [ImageContent('Kenya beans')]);
  });

  test('engine chrome like "Enable accessibility" is filtered out', () {
    const html =
        '<flt-semantics-host><flt-semantics role="button">'
        '<span>Enable accessibility</span></flt-semantics>'
        '<span>Real content</span></flt-semantics-host>';
    expect(extractor.extract(html), const [ParagraphContent('Real content')]);
  });

  test('adjacent duplicate nodes are collapsed', () {
    const html =
        '<flt-semantics-host><span>Same</span><span>Same</span>'
        '</flt-semantics-host>';
    expect(extractor.extract(html), const [ParagraphContent('Same')]);
  });

  test('mixed content keeps document order', () {
    const html = '''
<flt-semantics-host>
  <h1>Title</h1>
  <flt-semantics><span>Intro paragraph</span></flt-semantics>
  <a href="/next">Next page</a>
  <flt-semantics role="img" aria-label="A photo"></flt-semantics>
</flt-semantics-host>''';
    expect(extractor.extract(html), [
      HeadingContent('Title', level: 1),
      const ParagraphContent('Intro paragraph'),
      const LinkContent(href: '/next', text: 'Next page'),
      const ImageContent('A photo'),
    ]);
  });

  test('collapses runs of whitespace in recovered text', () {
    const html =
        '<flt-semantics-host><span>Line one\n   line two</span>'
        '</flt-semantics-host>';
    expect(extractor.extract(html), const [
      ParagraphContent('Line one line two'),
    ]);
  });
}
