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
