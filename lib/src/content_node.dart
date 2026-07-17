/// A single piece of crawlable content recovered from a Flutter semantics tree.
///
/// The prerender pipeline turns the accessibility DOM that Flutter renders into
/// an ordered list of [ContentNode]s, which the HTML builder then serialises
/// into real, visible markup (`<h1>`, `<p>`, `<a>`, `<img>`).
sealed class ContentNode {
  const ContentNode();

  /// The visible text carried by this node.
  ///
  /// For an [ImageContent] this is the alternative text.
  String get text;
}

/// A heading recovered from the semantics tree (`<h1>` .. `<h6>`).
final class HeadingContent extends ContentNode {
  /// Creates a heading at [level] (clamped to the 1..6 range) carrying [text].
  HeadingContent(this.text, {required int level})
    : level = level < 1 ? 1 : (level > 6 ? 6 : level);

  @override
  final String text;

  /// The heading level, always in the inclusive range 1..6.
  final int level;

  @override
  bool operator ==(Object other) =>
      other is HeadingContent && other.text == text && other.level == level;

  @override
  int get hashCode => Object.hash(text, level);

  @override
  String toString() => 'HeadingContent(h$level, "$text")';
}

/// A block of body text recovered from the semantics tree (`<p>`).
final class ParagraphContent extends ContentNode {
  /// Creates a paragraph carrying [text].
  const ParagraphContent(this.text);

  @override
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ParagraphContent && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'ParagraphContent("$text")';
}

/// A hyperlink recovered from the semantics tree (`<a href>`).
final class LinkContent extends ContentNode {
  /// Creates a link pointing at [href] with anchor [text].
  const LinkContent({required this.href, required this.text});

  @override
  final String text;

  /// The link target. May be a relative path (for example `/beans/kenya`).
  final String href;

  @override
  bool operator ==(Object other) =>
      other is LinkContent && other.href == href && other.text == text;

  @override
  int get hashCode => Object.hash(href, text);

  @override
  String toString() => 'LinkContent($href, "$text")';
}

/// An image recovered from the semantics tree, carrying its alternative text.
final class ImageContent extends ContentNode {
  /// Creates an image node with the given [alt] text.
  const ImageContent(this.alt);

  /// The alternative text describing the image.
  final String alt;

  @override
  String get text => alt;

  @override
  bool operator ==(Object other) => other is ImageContent && other.alt == alt;

  @override
  int get hashCode => alt.hashCode;

  @override
  String toString() => 'ImageContent("$alt")';
}
