/// The result of comparing the prerendered text against Flutter's own
/// accessibility text.
///
/// The prerender is built from Flutter's semantics tree, and this report
/// compares it against the text that same tree exposes as
/// `document.body.innerText` once accessibility is enabled, the only
/// machine-readable text the engine provides. It therefore catches extractor
/// drift and hand-edited output, but it cannot independently inspect the
/// painted canvas: there is no separate visible-text source to compare
/// against. A large [injectionRatio] means the generated HTML contains words
/// the accessibility text does not, which is the signal for injected,
/// crawler-only content.
final class ParityReport {
  /// Creates a parity report. Prefer [ParityGuard.compare] over calling this
  /// directly.
  const ParityReport({
    required this.similarity,
    required this.injectionRatio,
    required this.injectedWords,
    required this.missingWords,
    required this.threshold,
  });

  /// The Jaccard similarity of the two word sets, in the range 0.0..1.0.
  /// Reported for information; suspicion is driven by [injectionRatio].
  final double similarity;

  /// The fraction of generated words that do not appear in the app's rendered
  /// text, in the range 0.0..1.0.
  final double injectionRatio;

  /// Words present in the generated HTML but absent from the app's rendered
  /// text. A large set is a cloaking signal.
  final List<String> injectedWords;

  /// Words present in the app's rendered text but absent from the generated
  /// HTML. Informational: content the crawler will not see. Showing the
  /// crawler *less* than the user is incomplete coverage, not cloaking.
  final List<String> missingWords;

  /// The similarity threshold this report was evaluated against. The tolerated
  /// injection ratio is `1 - threshold`.
  final double threshold;

  /// Whether this report indicates a possible cloaking problem.
  ///
  /// True when the share of generated words the user never sees exceeds the
  /// tolerance `1 - threshold`. A faithful prerender, even one that covers
  /// only part of the page, has an injection ratio near zero and is not
  /// flagged.
  bool get isSuspicious => injectionRatio > (1 - threshold);

  @override
  String toString() =>
      'ParityReport(similarity: ${similarity.toStringAsFixed(3)}, '
      'injected: ${injectedWords.length}, missing: ${missingWords.length})';
}

/// Compares prerendered body text against the text a Flutter app renders and
/// reports any divergence.
final class ParityGuard {
  /// Creates a parity guard.
  ///
  /// [threshold] sets how much injected content is tolerated: a report is
  /// flagged when its injection ratio exceeds `1 - threshold`, so the default
  /// of 0.9 flags a page more than 10% of whose words the prerender never
  /// showed. It is not a similarity gate; a faithful prerender that covers
  /// only part of the page has a low similarity but a near-zero injection
  /// ratio and is not flagged. [minWordLength] filters out short tokens
  /// (punctuation fragments, articles) that would otherwise create noisy
  /// false positives.
  const ParityGuard({this.threshold = 0.9, this.minWordLength = 3});

  /// Controls the injection tolerance: a report is flagged when its injection
  /// ratio exceeds `1 - threshold`. See the constructor for why this is not a
  /// similarity gate.
  final double threshold;

  /// The minimum token length considered a meaningful word.
  final int minWordLength;

  static final RegExp _wordSplitter = RegExp('[^a-z0-9]+');

  /// Compares [sourceText] (what the app renders) with [generatedText] (what
  /// the prerenderer emitted) and returns a [ParityReport].
  ParityReport compare(String sourceText, String generatedText) {
    final source = _tokenize(sourceText);
    final generated = _tokenize(generatedText);
    final union = <String>{...source, ...generated};
    final intersection = source.intersection(generated);
    final similarity = union.isEmpty ? 1.0 : intersection.length / union.length;
    final injected = generated.difference(source).toList()..sort();
    final missing = source.difference(generated).toList()..sort();
    final injectionRatio = generated.isEmpty
        ? 0.0
        : injected.length / generated.length;
    return ParityReport(
      similarity: similarity,
      injectionRatio: injectionRatio,
      injectedWords: injected,
      missingWords: missing,
      threshold: threshold,
    );
  }

  Set<String> _tokenize(String text) => text
      .toLowerCase()
      .split(_wordSplitter)
      .where((word) => word.length >= minWordLength)
      .toSet();
}
