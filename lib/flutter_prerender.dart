/// Prerender a Flutter web app to static, crawlable HTML for SEO.
///
/// The public API is split into small, independently testable pieces:
///
/// * [PrerenderConfig] / [RouteSpec] / [RouteMeta]: configuration.
/// * [SemanticsExtractor]: recovers [ContentNode]s from a semantics DOM.
/// * [HtmlBuilder]: serialises content and metadata to static HTML.
/// * [buildSitemap]: emits `sitemap.xml`.
/// * [ParityGuard]: checks generated text against Flutter's semantics text.
/// * [PageCapturer] / [PuppeteerCapturer]: load a route in headless Chrome.
/// * [PrerenderEngine]: orchestrates the full run.
///
/// Most users invoke the bundled `flutter_prerender` command rather than the
/// library directly; see [runCli].
library;

export 'src/browser.dart';
export 'src/cli.dart';
export 'src/config.dart';
export 'src/content_node.dart';
export 'src/engine.dart';
export 'src/exceptions.dart';
export 'src/html_builder.dart';
export 'src/parity.dart';
export 'src/route_meta.dart';
export 'src/routes.dart';
export 'src/semantics_extractor.dart';
export 'src/sitemap.dart';
export 'src/static_server.dart';
