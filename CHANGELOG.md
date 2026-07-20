## 0.2.2

- Shorten the screenshot description. pub.dev accepts up to 200 characters but
  scores only those under 160, so the previous release published cleanly and
  quietly gave up the documentation points it was meant to earn.

## 0.2.1

- Declare the diagram in `pubspec.yaml` so pub.dev renders it on the package
  page. It was already in the repository and the README, but pub.dev shows only
  what the `screenshots:` field points at.

## 0.2.0

- Add `--robots`, which writes a `robots.txt` declaring the generated sitemap.
  The tool produced a `sitemap.xml` that nothing pointed at; the `Sitemap:`
  directive is the documented way to announce one and is what webmaster tools
  and non-Google crawlers read. The line is only written when a sitemap was
  actually produced, so a crawler is never sent to a URL that would 404.
- The flag is off by default and never replaces an existing `robots.txt`. A
  project that ships `web/robots.txt` has it copied into the build, and
  silently overwriting crawl rules somebody wrote on purpose would be a worse
  bug than not writing the file; the existing one is left alone and the run
  reports it as a warning.
- Fix `dart analyze` reporting dozens of errors on a clean checkout. The
  example is a Flutter app, so the package's pure-Dart analyzer could not
  resolve any widget in it and called every one undefined. It is excluded from
  the package's analysis and still checked on its own terms with
  `cd example && flutter analyze`.

## 0.1.2

- Docs: make clear up front that this is a command-line tool you run against a
  `flutter build web` output, not a package you add to an app's dependencies.
  Also clarifies why pub.dev lists the platforms the tool runs on (Linux, macOS,
  Windows) rather than web.

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
