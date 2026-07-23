## 1.0.0

First stable release. From here the public API follows semantic versioning: a
breaking change will not land without a major-version bump.

- Seal the 20 leaf classes that make up the public surface (`PrerenderConfig`,
  `PrerenderResult`, `RouteSpec`, the exception types, and the rest) with
  `final`. They are meant to be constructed and read, not extended, and nothing
  in the package or its tests subtypes them. This keeps the rest of 1.x
  additive: `PrerenderResult` gained `failedRoutes` in 0.3.1 and
  `PrerenderConfig` grows fields most minors, and each such addition would break
  an external `implements`. `PageCapturer` stays an open interface, because
  faking it is how the pipeline is tested, `ContentNode` stays `sealed` with
  its four `final` variants, and `PrerenderException` stays open as an
  extensible base.
- Correct the documented meaning of `parityThreshold`. Its field and help text
  called it a minimum acceptable content similarity, but the guard flags on the
  injection ratio: a page is suspicious when more than `1 - threshold` of its
  words were never shown, and similarity never drives the decision. A prerender
  that faithfully covers part of a page has low similarity and is not flagged.
  The docs now say what the code does, before 1.0.0 freezes the wrong contract.
- Fix `--version`, which printed `0.1.0` in every release since 0.1.0 because a
  hand-maintained constant was never bumped. It is correct now, and a test
  reads `pubspec.yaml` and fails if the two ever drift again.

## 0.3.2

- Fix a route being able to write its `index.html` outside the output
  directory. A route is turned into a path under `--out`, but `normalizeRoute`
  only ensured a single leading slash: a `..` segment (`../secret`) wrote above
  the output directory, and a leading `//` (`//etc/passwd`) became an absolute
  path that `path.join` honoured, discarding `--out` entirely. This was
  reachable from a plain routes file or a YAML config, not only `--crawl`, and
  had been present since 0.1.0. `normalizeRoute` now rejects both shapes;
  discovered crawl links that would traverse are skipped rather than aborting
  the crawl; and the writer refuses any target outside the output directory as
  a second layer. Ordinary routes, and a safe absolute link like `/../about`
  that cannot climb above root, are unaffected.

## 0.3.1

- Fix `--crawl` aborting the whole run and discarding every page already
  rendered when it followed a same-origin link to something that is not a
  Flutter route, such as a PDF or an image linked from the site's own nav or
  footer. The browser capturer already treats an empty semantics tree and
  empty rendered text as "this page never booted a Flutter app" and throws;
  the engine now catches that per route instead of letting it escape `run()`
  and take down the whole prerender. Every route rendered before the failure
  keeps its file and its sitemap entry.
- The failed route is recorded in the new `PrerenderResult.failedRoutes`,
  printed in the CLI summary, and reported as a warning on `stderr`.
  `--fail-on-empty` also exits non-zero when a route failed to capture.

## 0.3.0

- Add `--crawl`, which discovers routes by following the in-page links the
  engine already recovers instead of prerendering only the listed routes. The
  routes you pass (or `/` when you pass none) seed a work queue, every
  same-origin link found on a page is normalised and enqueued if it has not
  been seen, and the crawl stops at `--max-pages` (default 100). Off-site
  links, `mailto:`/`tel:`, and bare fragments are skipped; an absolute URL is
  followed only when its origin matches `--base-url`. Without `--crawl` nothing
  changes: the tool still prerenders exactly the routes you list.
- The sitemap now lists the pages that were actually prerendered rather than
  the configured route list, so a crawl's discovered pages are included. For a
  fixed route list the output is the same as before.

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
