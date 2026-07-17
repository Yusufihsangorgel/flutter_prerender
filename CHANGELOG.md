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
- Content-parity guard that warns (or fails, with `--fail-on-parity`) when the
  generated HTML diverges from what the app renders.
- YAML config file and command-line flags, with flags overriding the file.
