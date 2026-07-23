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
    final rawJsonLd = map['jsonLd'] ?? map['json_ld'];
    return RouteMeta(
      title: map['title'] as String?,
      description: map['description'] as String?,
      image: map['image'] as String?,
      canonical: map['canonical'] as String?,
      ogType: (map['ogType'] ?? map['og_type']) as String?,
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
