import 'dart:io';

import 'package:path/path.dart' as p;

import 'browser.dart';
import 'config.dart';
import 'content_node.dart';
import 'html_builder.dart';
import 'parity.dart';
import 'semantics_extractor.dart';
import 'sitemap.dart';

/// The outcome of prerendering a single route.
class RouteResult {
  /// Creates a [RouteResult].
  const RouteResult({
    required this.path,
    required this.outputPath,
    required this.nodeCount,
    required this.byteCount,
    this.parity,
    this.warnings = const <String>[],
  });

  /// The route path that was prerendered.
  final String path;

  /// The absolute path of the written HTML file.
  final String outputPath;

  /// The number of content nodes recovered from the semantics tree.
  final int nodeCount;

  /// The size of the written HTML file in bytes.
  final int byteCount;

  /// The content-parity report, or `null` if the guard was disabled.
  final ParityReport? parity;

  /// Human-readable warnings raised for this route (empty output, duplicate
  /// content, and so on).
  final List<String> warnings;

  /// Whether this route recovered no crawlable content.
  bool get isEmpty => nodeCount == 0;
}

/// The outcome of a complete prerender run.
class PrerenderResult {
  /// Creates a [PrerenderResult].
  const PrerenderResult({
    required this.routes,
    this.sitemapPath,
    this.runWarnings = const <String>[],
  });

  /// Per-route results, in the order the routes were prerendered.
  final List<RouteResult> routes;

  /// The absolute path of the written `sitemap.xml`, or `null` if none.
  final String? sitemapPath;

  /// Warnings that concern the run as a whole rather than a single route.
  final List<String> runWarnings;

  /// Whether any route produced a suspicious parity report.
  bool get hasParityWarnings =>
      routes.any((r) => r.parity?.isSuspicious ?? false);

  /// Whether any route recovered no crawlable content.
  bool get hasEmptyRoutes => routes.any((r) => r.isEmpty);

  /// Every warning from the run, run-level first, then per-route.
  List<String> get allWarnings => [
    ...runWarnings,
    for (final route in routes)
      for (final warning in route.warnings) '${route.path}: $warning',
  ];
}

/// Drives the end-to-end prerender: capture each route, recover content,
/// build HTML, run the parity guard, write files, and emit a sitemap.
class PrerenderEngine {
  /// Creates an engine from [config] and a [capturer].
  PrerenderEngine({
    required this.config,
    required this.capturer,
    SemanticsExtractor? extractor,
  }) : extractor = extractor ?? SemanticsExtractor(),
       _builder = HtmlBuilder(
         lang: config.lang,
         includeAppScript: config.includeAppScript,
         appScriptSrc: config.appScriptSrc,
         baseHref: config.baseHref,
       ),
       _guard = ParityGuard(threshold: config.parityThreshold);

  /// The resolved configuration for this run.
  final PrerenderConfig config;

  /// The browser-backed capturer.
  final PageCapturer capturer;

  /// The semantics-to-content extractor.
  final SemanticsExtractor extractor;

  final HtmlBuilder _builder;
  final ParityGuard _guard;

  /// Runs the prerender.
  ///
  /// [baseUri] is the root of the running static server (routes are resolved
  /// against it). [log] receives human-readable progress lines.
  Future<PrerenderResult> run(Uri baseUri, {void Function(String)? log}) async {
    final outDir = Directory(p.normalize(p.absolute(config.outDir)));
    outDir.createSync(recursive: true);

    final runWarnings = _preflightWarnings();
    for (final warning in runWarnings) {
      log?.call('warning: $warning');
    }

    final results = <RouteResult>[];
    final signatureToRoute = <String, String>{};
    for (final spec in config.routes) {
      log?.call('Prerendering ${spec.path} ...');
      final captured = await capturer.capture(baseUri.resolve(spec.path));
      final nodes = extractor.extract(captured.semanticsHtml);
      final meta = spec.meta.merge(config.defaults);
      final pageUrl = config.baseUrl == null
          ? null
          : joinUrl(config.baseUrl!, spec.path);
      final html = _builder.build(
        nodes: nodes,
        meta: meta,
        fallbackTitle: captured.title,
        pageUrl: pageUrl,
      );

      final warnings = <String>[];
      ParityReport? parity;
      if (nodes.isEmpty) {
        warnings.add(
          'no crawlable content recovered; check --build-dir and that this '
          'route renders text',
        );
      } else {
        final signature = _signature(nodes);
        final firstSeen = signatureToRoute[signature];
        if (firstSeen != null) {
          warnings.add(
            'produced the same content as $firstSeen; the app may not be '
            'routing on the path',
          );
        } else {
          signatureToRoute[signature] = spec.path;
        }
      }

      if (config.parityCheck) {
        parity = _guard.compare(captured.renderedText, _bodyText(nodes));
        if (parity.isSuspicious) {
          warnings.add(
            'parity: similarity ${parity.similarity.toStringAsFixed(2)}, '
            '${parity.injectedWords.length} injected word(s)',
          );
        }
      }

      for (final warning in warnings) {
        log?.call('  warning: $warning');
      }

      final file = _writeRoute(outDir.path, spec.path, html);
      results.add(
        RouteResult(
          path: spec.path,
          outputPath: file.path,
          nodeCount: nodes.length,
          byteCount: file.lengthSync(),
          parity: parity,
          warnings: warnings,
        ),
      );
    }

    String? sitemapPath;
    if (config.generateSitemap &&
        config.baseUrl != null &&
        config.routes.isNotEmpty) {
      final xml = buildSitemap(
        config.routes.map(
          (spec) => SitemapEntry(joinUrl(config.baseUrl!, spec.path)),
        ),
      );
      final sitemapFile = File(p.join(outDir.path, 'sitemap.xml'))
        ..writeAsStringSync(xml);
      sitemapPath = sitemapFile.path;
      log?.call('Wrote ${sitemapFile.path}');
    }

    return PrerenderResult(
      routes: results,
      sitemapPath: sitemapPath,
      runWarnings: runWarnings,
    );
  }

  List<String> _preflightWarnings() {
    final warnings = <String>[];
    if (config.generateSitemap && config.baseUrl == null) {
      warnings.add(
        'sitemap requested but no baseUrl is set; skipping sitemap.xml',
      );
    }
    final hasNestedRoute = config.routes.any(
      (spec) => spec.path.split('/').where((s) => s.isNotEmpty).length > 1,
    );
    final relativeAppScript =
        !config.appScriptSrc.startsWith('/') &&
        !config.appScriptSrc.contains('://');
    if (config.includeAppScript &&
        hasNestedRoute &&
        relativeAppScript &&
        config.baseHref == null) {
      warnings.add(
        'appScriptSrc "${config.appScriptSrc}" is relative and some routes are '
        'nested; the bootstrap script may 404 on deep routes. Use an absolute '
        '"/..." path or set baseHref.',
      );
    }
    return warnings;
  }

  static File _writeRoute(String outDir, String route, String html) {
    final relative = route == '/' ? '' : route.replaceFirst('/', '');
    final dir = Directory(p.join(outDir, relative))
      ..createSync(recursive: true);
    final file = File(p.join(dir.path, 'index.html'))..writeAsStringSync(html);
    return file;
  }

  // Image alt text comes from aria-labels, not document.body.innerText, so it
  // is excluded from the parity comparison: describing a visible image is
  // standard SEO, not injected crawler-only prose.
  static String _bodyText(List<ContentNode> nodes) => nodes
      .where((node) => node is! ImageContent)
      .map((node) => node.text)
      .join(' ');

  static String _signature(List<ContentNode> nodes) => nodes
      .map(
        (node) => switch (node) {
          LinkContent(:final href, :final text) => 'a:$href:$text',
          _ => '${node.runtimeType}:${node.text}',
        },
      )
      .join('|');
}
