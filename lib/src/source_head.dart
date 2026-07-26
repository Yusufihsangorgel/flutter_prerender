import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// The parts of a Flutter build's own `index.html` head that a prerendered
/// page has to keep.
///
/// Prerendering replaces the document a visitor receives, so anything the
/// Flutter build put in the head and the generated page does not reproduce is
/// simply gone: the PWA manifest, the favicon, the theme colour, and most
/// consequentially `<base href>`, without which `flutter_bootstrap.js` resolves
/// `main.dart.js` against the deep route it was served from and the app never
/// boots.
///
/// Only tags the generator does not emit itself are carried, so a title or
/// description computed per route still wins over the one baked into the build.
final class SourceHead {
  const SourceHead._({required this.baseHref, required this.carried});

  /// The build's `<base href>`, or null when it has none.
  ///
  /// A built `index.html` normally has one: Flutter substitutes its
  /// `$FLUTTER_BASE_HREF` placeholder at build time, defaulting to `/`.
  final String? baseHref;

  /// Serialized head elements to copy into every generated page, in source
  /// order.
  final List<String> carried;

  /// Nothing to carry. Used when there is no build to read.
  static const SourceHead empty = SourceHead._(baseHref: null, carried: []);

  /// Reads what is worth keeping out of [indexHtml].
  factory SourceHead.parse(String indexHtml) {
    final head = html_parser.parse(indexHtml).head;
    if (head == null) return empty;

    String? baseHref;
    final carried = <String>[];

    for (final element in head.children) {
      final name = element.localName;
      if (name == 'base') {
        final href = element.attributes['href'];
        // An unsubstituted placeholder means we are looking at the source
        // template rather than a build; treat it as the default root.
        baseHref = href == null || href.startsWith(r'$') ? '/' : href;
        continue;
      }
      if (_shouldCarry(element)) carried.add(element.outerHtml);
    }

    return SourceHead._(baseHref: baseHref, carried: carried);
  }

  /// Whether [element] belongs in the generated head.
  ///
  /// The generator writes charset, viewport, title, description, canonical,
  /// Open Graph, Twitter cards and JSON-LD itself, per route, so those are
  /// dropped here rather than duplicated. Everything else the build asked for
  /// is kept: it is there because the app needs it.
  static bool _shouldCarry(dom.Element element) {
    switch (element.localName) {
      case 'title':
        return false;
      case 'script':
        // The generated page loads the app itself, and a build's inline
        // service-worker bootstrap re-registers against the wrong scope from a
        // deep route.
        return false;
      case 'meta':
        if (element.attributes.containsKey('charset')) return false;
        final name = element.attributes['name']?.toLowerCase();
        final property = element.attributes['property']?.toLowerCase();
        if (name == 'viewport' || name == 'description') return false;
        if (name != null && name.startsWith('twitter:')) return false;
        if (property != null && property.startsWith('og:')) return false;
        return true;
      case 'link':
        final rel = element.attributes['rel']?.toLowerCase();
        return rel != 'canonical';
      default:
        return true;
    }
  }
}
