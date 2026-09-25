import 'exceptions.dart';

/// SEO metadata for a single prerendered route.
///
/// Any field left `null` falls back to the corresponding value from the
/// document defaults (see [merge]).
final class RouteMeta {
  /// Creates a [RouteMeta]. All fields are optional.
  const RouteMeta({
    this.title,
    this.description,
    this.image,
    this.canonical,
    this.ogType,
    this.jsonLd,
  });

  /// Builds a [RouteMeta] from a decoded map (for example a YAML mapping).
  ///
  /// Recognised keys: `title`, `description`, `image`, `canonical`, `ogType`
  /// (or `og_type`), and `jsonLd` (or `json_ld`). Unknown keys are ignored.
  factory RouteMeta.fromMap(Map<String, Object?> map) {
    final jsonLdKey = map['jsonLd'] != null ? 'jsonLd' : 'json_ld';
    final rawJsonLd = map[jsonLdKey];
    if (rawJsonLd != null && rawJsonLd is! Map) {
      throw ConfigException('"$jsonLdKey" must be a mapping.');
    }
    return RouteMeta(
      title: _string(map, 'title'),
      description: _string(map, 'description'),
      image: _string(map, 'image'),
      canonical: _string(map, 'canonical'),
      ogType: _string(map, 'ogType') ?? _string(map, 'og_type'),
      jsonLd: rawJsonLd is Map ? _deepMap(rawJsonLd) : null,
    );
  }

  /// The document title (`<title>` and `og:title`).
  final String? title;

  /// The meta description and `og:description`.
  final String? description;

  /// An absolute URL to a preview image (`og:image`, `twitter:image`).
  final String? image;

  /// The canonical URL for this route (`<link rel="canonical">`).
  final String? canonical;

  /// The Open Graph object type (`og:type`), for example `website` or
  /// `article`. Defaults to `website` when never set.
  final String? ogType;

  /// A schema.org object rendered as a JSON-LD `<script>` block.
  final Map<String, Object?>? jsonLd;

  static String? _string(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is String) return value;
    throw ConfigException('"$key" must be a string.');
  }

  /// Returns a new [RouteMeta] where each `null` field is filled in from
  /// [defaults].
  RouteMeta merge(RouteMeta defaults) => RouteMeta(
    title: title ?? defaults.title,
    description: description ?? defaults.description,
    image: image ?? defaults.image,
    canonical: canonical ?? defaults.canonical,
    ogType: ogType ?? defaults.ogType,
    jsonLd: jsonLd ?? defaults.jsonLd,
  );

  static Map<String, Object?> _deepMap(Map<Object?, Object?> source) {
    return <String, Object?>{
      for (final entry in source.entries)
        entry.key.toString(): _deepValue(entry.value),
    };
  }

  static Object? _deepValue(Object? value) {
    if (value is Map) return _deepMap(value);
    if (value is List) return value.map(_deepValue).toList();
    return value;
  }
}
