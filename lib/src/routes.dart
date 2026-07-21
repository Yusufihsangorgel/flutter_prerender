import 'exceptions.dart';

/// Parses the contents of a plain-text routes file into normalised route paths.
///
/// The format is one route per line. Blank lines and lines beginning with `#`
/// are ignored. Each route is normalised to start with a single leading slash,
/// and duplicates are removed while preserving first-seen order.
///
/// Throws a [ConfigException] if a line looks like an absolute URL (contains
/// `://`) or contains whitespace inside the path.
List<String> parseRoutesFile(String content) {
  final seen = <String>{};
  final routes = <String>[];
  var lineNumber = 0;
  for (final rawLine in content.split('\n')) {
    lineNumber++;
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    routes.add(normalizeRoute(line, lineNumber: lineNumber));
  }
  return [
    for (final route in routes)
      if (seen.add(route)) route,
  ];
}

/// Normalises a single route path.
///
/// Ensures a single leading slash and rejects absolute URLs or paths
/// containing whitespace. [lineNumber], when provided, is included in error
/// messages to help users locate the offending entry.
String normalizeRoute(String raw, {int? lineNumber}) {
  final value = raw.trim();
  final where = lineNumber == null ? '' : ' (line $lineNumber)';
  if (value.contains('://')) {
    throw ConfigException(
      'Route must be a path, not an absolute URL: "$value"$where',
    );
  }
  if (RegExp(r'\s').hasMatch(value)) {
    throw ConfigException('Route must not contain whitespace: "$value"$where');
  }
  if (value == '/') return '/';
  final withoutTrailing = value.endsWith('/')
      ? value.substring(0, value.length - 1)
      : value;
  return withoutTrailing.startsWith('/')
      ? withoutTrailing
      : '/$withoutTrailing';
}

/// Resolves a discovered link [href] to a same-origin route path, or returns
/// `null` when the link is not a crawlable page on this site.
///
/// Relative and root-relative links (`/about`, `beans/kenya`, `/x?y=1#z`) are
/// same-origin by construction; their query and fragment are dropped and the
/// path is normalised with [normalizeRoute]. An absolute `http`/`https` URL is
/// kept only when [origin] is given and its host and port match; every other
/// absolute URL, a scheme-relative `//host/path`, a `mailto:`/`tel:` link, and
/// a bare `#fragment` return `null`.
String? sameOriginRoute(String href, {String? origin}) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.hasScheme) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (origin == null) return null;
    final originUri = Uri.tryParse(origin);
    if (originUri == null) return null;
    if (uri.host != originUri.host || uri.port != originUri.port) return null;
    return _routeFromPath(uri.path);
  }
  // A scheme-relative link points at an origin we cannot confirm.
  if (uri.hasAuthority) return null;
  return _routeFromPath(uri.path);
}

String? _routeFromPath(String path) {
  if (path.isEmpty) return null;
  return normalizeRoute(path);
}

/// Selects new same-origin routes discovered from a page's link [hrefs].
///
/// Each href is resolved with [sameOriginRoute], dropped when off-site or
/// already present in [known], and de-duplicated. At most [limit] new routes
/// are returned, in first-seen order. [known] is not mutated.
List<String> discoverRoutes(
  Iterable<String> hrefs, {
  required Set<String> known,
  required int limit,
  String? origin,
}) {
  if (limit <= 0) return const <String>[];
  final discovered = <String>[];
  final seen = <String>{...known};
  for (final href in hrefs) {
    if (discovered.length >= limit) break;
    final route = sameOriginRoute(href, origin: origin);
    if (route == null) continue;
    if (seen.add(route)) discovered.add(route);
  }
  return discovered;
}
