import 'package:yaml/yaml.dart';

import 'exceptions.dart';
import 'route_meta.dart';
import 'routes.dart';

/// A route to prerender together with its per-route SEO metadata.
class RouteSpec {
  /// Creates a route spec for [path] with optional [meta].
  const RouteSpec(this.path, {this.meta = const RouteMeta()});

  /// The normalised route path (for example `/` or `/beans/kenya`).
  final String path;

  /// SEO metadata for this route, before merging with document defaults.
  final RouteMeta meta;
}

/// The fully resolved configuration for a prerender run.
///
/// Build a [PrerenderConfig] from a YAML file with [PrerenderConfig.fromYaml],
/// then apply command-line overrides with [copyWith].
class PrerenderConfig {
  /// Creates a [PrerenderConfig]. All parameters have sensible defaults.
  const PrerenderConfig({
    this.buildDir = 'build/web',
    this.outDir = 'build/prerendered',
    this.baseUrl,
    this.routes = const <RouteSpec>[],
    this.defaults = const RouteMeta(),
    this.generateSitemap = true,
    this.generateRobots = false,
    this.includeAppScript = true,
    this.appScriptSrc = '/flutter_bootstrap.js',
    this.parityCheck = true,
    this.parityThreshold = 0.9,
    this.failOnParity = false,
    this.failOnEmpty = false,
    this.waitMs = 4000,
    this.port = 0,
    this.chromeExecutable,
    this.lang = 'en',
    this.baseHref,
  });

  /// Parses a YAML document into a [PrerenderConfig].
  ///
  /// Throws a [ConfigException] if the document is not a mapping or a field
  /// has the wrong type.
  factory PrerenderConfig.fromYaml(String yaml) {
    final Object? doc;
    try {
      doc = loadYaml(yaml);
    } on YamlException catch (error) {
      throw ConfigException('Invalid YAML: ${error.message}');
    }
    if (doc == null) return const PrerenderConfig();
    if (doc is! Map) {
      throw const ConfigException('Config root must be a mapping.');
    }
    return PrerenderConfig.fromMap(_toStringMap(doc));
  }

  /// Builds a [PrerenderConfig] from a decoded map.
  factory PrerenderConfig.fromMap(Map<String, Object?> map) {
    // `parity` may be a boolean shorthand (`parity: false`) or a mapping with
    // `enabled`/`threshold`/`failOn`.
    final parity = map['parity'];
    bool? parityShorthand;
    Map<String, Object?> parityMap = const <String, Object?>{};
    if (parity is bool) {
      parityShorthand = parity;
    } else if (parity is Map) {
      parityMap = _toStringMap(parity);
    } else if (parity != null) {
      throw const ConfigException('"parity" must be a boolean or a mapping.');
    }
    return PrerenderConfig(
      buildDir: _string(map, 'buildDir') ?? 'build/web',
      outDir:
          _string(map, 'out') ?? _string(map, 'outDir') ?? 'build/prerendered',
      baseUrl: _string(map, 'baseUrl'),
      lang: _string(map, 'lang') ?? 'en',
      baseHref: _string(map, 'baseHref'),
      generateSitemap: _bool(map, 'sitemap') ?? true,
      generateRobots: _bool(map, 'robots') ?? false,
      includeAppScript: _bool(map, 'appScript') ?? true,
      appScriptSrc: _string(map, 'appScriptSrc') ?? '/flutter_bootstrap.js',
      parityCheck: parityShorthand ?? _bool(parityMap, 'enabled') ?? true,
      parityThreshold: _double(parityMap, 'threshold') ?? 0.9,
      failOnParity: _bool(parityMap, 'failOn') ?? false,
      failOnEmpty: _bool(map, 'failOnEmpty') ?? false,
      waitMs: _int(map, 'waitMs') ?? 4000,
      port: _int(map, 'port') ?? 0,
      chromeExecutable:
          _string(map, 'chrome') ?? _string(map, 'chromeExecutable'),
      defaults: map['defaults'] is Map
          ? RouteMeta.fromMap(_toStringMap(map['defaults'] as Map))
          : const RouteMeta(),
      routes: _parseRoutes(map['routes']),
    );
  }

  /// Directory containing the `flutter build web` output.
  final String buildDir;

  /// Directory the prerendered HTML and sitemap are written to.
  final String outDir;

  /// The public site origin (for example `https://example.com`), used for
  /// canonical URLs, `og:url` and the sitemap.
  final String? baseUrl;

  /// The routes to prerender.
  final List<RouteSpec> routes;

  /// Document-wide metadata defaults, merged into every route.
  final RouteMeta defaults;

  /// Whether to write a `sitemap.xml` (requires [baseUrl]).
  final bool generateSitemap;

  /// Whether to write a `robots.txt` that points crawlers at the sitemap.
  ///
  /// Off by default, and never overwrites a `robots.txt` that is already in
  /// the output: a Flutter project that ships `web/robots.txt` has it copied
  /// into the build, and silently replacing someone's crawl rules would be a
  /// worse bug than not writing the file. An existing file is left alone and
  /// reported as a warning instead.
  final bool generateRobots;

  /// Whether the generated pages load the original Flutter app.
  final bool includeAppScript;

  /// The `src` of the Flutter bootstrap script in generated pages.
  final String appScriptSrc;

  /// Whether to run the content-parity guard after building each page.
  final bool parityCheck;

  /// Minimum acceptable content similarity before a page is flagged.
  final double parityThreshold;

  /// Whether a suspicious parity report should make the run exit non-zero.
  final bool failOnParity;

  /// Whether a route that recovers no content should make the run exit
  /// non-zero.
  final bool failOnEmpty;

  /// Extra milliseconds to wait after the semantics tree appears, giving the
  /// app time to finish laying out.
  final int waitMs;

  /// The port for the local static server. `0` selects a free port.
  final int port;

  /// An explicit path to a Chrome/Chromium executable. When `null`,
  /// `package:puppeteer` downloads and manages its own copy.
  final String? chromeExecutable;

  /// The `lang` attribute written into generated pages.
  final String lang;

  /// An optional `<base href>` written into generated pages.
  final String? baseHref;

  /// Returns a copy of this config with the given non-null fields replaced.
  ///
  /// Used to layer command-line flags over a config file.
  PrerenderConfig copyWith({
    String? buildDir,
    String? outDir,
    String? baseUrl,
    List<RouteSpec>? routes,
    bool? generateSitemap,
    bool? generateRobots,
    bool? includeAppScript,
    bool? parityCheck,
    double? parityThreshold,
    bool? failOnParity,
    bool? failOnEmpty,
    int? waitMs,
    int? port,
    String? chromeExecutable,
    String? lang,
    String? baseHref,
  }) {
    return PrerenderConfig(
      buildDir: buildDir ?? this.buildDir,
      outDir: outDir ?? this.outDir,
      baseUrl: baseUrl ?? this.baseUrl,
      routes: routes ?? this.routes,
      defaults: defaults,
      generateSitemap: generateSitemap ?? this.generateSitemap,
      generateRobots: generateRobots ?? this.generateRobots,
      includeAppScript: includeAppScript ?? this.includeAppScript,
      appScriptSrc: appScriptSrc,
      parityCheck: parityCheck ?? this.parityCheck,
      parityThreshold: parityThreshold ?? this.parityThreshold,
      failOnParity: failOnParity ?? this.failOnParity,
      failOnEmpty: failOnEmpty ?? this.failOnEmpty,
      waitMs: waitMs ?? this.waitMs,
      port: port ?? this.port,
      chromeExecutable: chromeExecutable ?? this.chromeExecutable,
      lang: lang ?? this.lang,
      baseHref: baseHref ?? this.baseHref,
    );
  }

  static List<RouteSpec> _parseRoutes(Object? raw) {
    if (raw == null) return const <RouteSpec>[];
    if (raw is! List) {
      throw const ConfigException('"routes" must be a list.');
    }
    final specs = <RouteSpec>[];
    for (final entry in raw) {
      if (entry is String) {
        specs.add(RouteSpec(normalizeRoute(entry)));
      } else if (entry is Map) {
        final map = _toStringMap(entry);
        final path = map['path'];
        if (path is! String) {
          throw const ConfigException('Each route needs a string "path".');
        }
        specs.add(
          RouteSpec(normalizeRoute(path), meta: RouteMeta.fromMap(map)),
        );
      } else {
        throw ConfigException('Invalid route entry: $entry');
      }
    }
    return specs;
  }

  static Map<String, Object?> _toStringMap(Map<Object?, Object?> source) => {
    for (final entry in source.entries) entry.key.toString(): entry.value,
  };

  static String? _string(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is String) return value;
    throw ConfigException('"$key" must be a string.');
  }

  static bool? _bool(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is bool) return value;
    throw ConfigException('"$key" must be a boolean.');
  }

  static int? _int(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is int) return value;
    throw ConfigException('"$key" must be an integer.');
  }

  static double? _double(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    throw ConfigException('"$key" must be a number.');
  }
}
