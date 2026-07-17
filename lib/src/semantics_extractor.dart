import 'package:html/dom.dart';
import 'package:html/parser.dart';

import 'content_node.dart';

/// Recovers an ordered list of [ContentNode]s from the HTML of a Flutter
/// semantics tree (`<flt-semantics-host>` and its descendants).
///
/// Flutter web draws its UI to a canvas, so the visible pixels carry no text.
/// When the accessibility (semantics) tree is enabled, however, the engine
/// mirrors the widget tree into a hidden DOM: real `<h1>`..`<h6>` for
/// `Semantics(headingLevel:)`, real `<a href>` for [Link] widgets, and
/// `role="img"` elements for `Semantics(image:)`. This extractor walks that
/// DOM in document order and classifies each text-bearing leaf.
///
/// The class is deliberately free of any browser dependency: it operates on a
/// plain HTML string, which makes the recovery logic fully unit-testable.
class SemanticsExtractor {
  /// Creates a semantics extractor.
  ///
  /// [ignoredLabels] lists text values that are engine chrome rather than app
  /// content and should be dropped (for example the "Enable accessibility"
  /// placeholder button).
  SemanticsExtractor({Set<String>? ignoredLabels})
    : _ignored = {
        for (final label in ignoredLabels ?? _defaultIgnored)
          label.toLowerCase(),
      };

  static const Set<String> _defaultIgnored = {'Enable accessibility'};

  final Set<String> _ignored;

  static final RegExp _headingTag = RegExp(r'^h[1-6]$');

  /// Parses [semanticsHtml] and returns the recovered content in document
  /// order.
  ///
  /// An empty or structureless input yields an empty list rather than throwing.
  List<ContentNode> extract(String semanticsHtml) {
    if (semanticsHtml.trim().isEmpty) {
      return const <ContentNode>[];
    }
    final fragment = parseFragment(semanticsHtml);
    final nodes = <ContentNode>[];
    for (final element in fragment.children) {
      _walk(element, nodes);
    }
    return _dedupeAdjacent(nodes);
  }

  void _walk(Element element, List<ContentNode> out) {
    final tag = element.localName?.toLowerCase() ?? '';
    final role = element.attributes['role'];

    // Headings: real <h1>..<h6> or role="heading" with aria-level.
    if (_headingTag.hasMatch(tag)) {
      _emitHeading(out, int.parse(tag.substring(1)), element.text);
      return;
    }
    if (role == 'heading') {
      final level = int.tryParse(element.attributes['aria-level'] ?? '') ?? 2;
      _emitHeading(out, level, element.text);
      return;
    }

    // Links: real <a href> or role="link".
    if (tag == 'a' && element.attributes.containsKey('href')) {
      _emitLink(out, element.attributes['href'] ?? '', element.text);
      return;
    }
    if (role == 'link') {
      final anchor = element.querySelector('a[href]');
      final href =
          element.attributes['href'] ?? anchor?.attributes['href'] ?? '';
      _emitLink(out, href, element.text);
      return;
    }

    // Images: real <img> or role="img" with a label.
    if (tag == 'img') {
      _emitImage(out, element.attributes['alt'] ?? '');
      return;
    }
    if (role == 'img') {
      _emitImage(
        out,
        element.attributes['aria-label'] ?? element.attributes['alt'] ?? '',
      );
      return;
    }

    // Structural node: recurse into element children, or emit leaf text.
    final childElements = element.children;
    if (childElements.isEmpty) {
      _emitParagraph(out, element.text);
      return;
    }
    for (final child in childElements) {
      _walk(child, out);
    }
  }

  void _emitHeading(List<ContentNode> out, int level, String raw) {
    final text = _clean(raw);
    if (text.isEmpty || _isIgnored(text)) return;
    out.add(HeadingContent(text, level: level));
  }

  void _emitParagraph(List<ContentNode> out, String raw) {
    final text = _clean(raw);
    if (text.isEmpty || _isIgnored(text)) return;
    out.add(ParagraphContent(text));
  }

  void _emitLink(List<ContentNode> out, String href, String raw) {
    final text = _clean(raw);
    if (text.isEmpty || _isIgnored(text)) return;
    out.add(LinkContent(href: href.trim(), text: text));
  }

  void _emitImage(List<ContentNode> out, String raw) {
    final alt = _clean(raw);
    if (alt.isEmpty || _isIgnored(alt)) return;
    out.add(ImageContent(alt));
  }

  bool _isIgnored(String text) => _ignored.contains(text.toLowerCase());

  String _clean(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();

  List<ContentNode> _dedupeAdjacent(List<ContentNode> nodes) {
    final result = <ContentNode>[];
    for (final node in nodes) {
      if (result.isNotEmpty && result.last == node) continue;
      result.add(node);
    }
    return result;
  }
}
