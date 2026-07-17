## 0.1.1

- Docs: tightened the README wording and visuals.

# Changelog

## 0.1.0

Initial release.

- CLI (`flutter_prerender`) that prerenders a `flutter build web` output to
  static, crawlable HTML, one file per route.
- Recovers headings, paragraphs, links and image alt text from Flutter's
  accessibility tree without changing app source.
- Injects `<title>`, meta description, canonical, Open Graph, Twitter Card and
  optional JSON-LD per route.
- Generates `sitemap.xml`.
- Parity guard that compares the generated HTML against Flutter's own
  accessibility text and warns (or fails, with `--fail-on-parity`) on injected
  content.
- Warnings for routes that recover no content (`--fail-on-empty` to make it
  fatal) and for routes that duplicate another route's content.
- YAML config file and command-line flags, with flags overriding the file.
  Invalid numeric flags are rejected instead of silently ignored.
