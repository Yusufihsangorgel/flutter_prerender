## 1.3.2

- `packageVersion` was left at 1.2.0 while the pubspec moved to 1.3.1, so
  `--version` reported the wrong number and the test that guards exactly this
  was red through two releases. The constant is hand-maintained and the guard
  exists because it has drifted before; it was not run before those two went
  out. It is in step again.
- Added `example/what_a_crawler_sees.dart`, which reads the same build before
  and after prerendering and counts what is actually in each: zero words of
  body text against fifty-two, the generated title against the real one, and
  Open Graph and JSON-LD present rather than absent. The README opens with a
  recording of it.

## 1.3.1

- The section on why to reach for this rather than the alternative now sits at
  the top, where someone deciding whether to install it will read it, instead
  of below a long explanation.

## 1.3.0

- The README now answers, in its first screen, why to reach for this rather
  than the zero-dependency route or the package that already owns the
  category. Both answers carry the file and line, or the issue number, that
  a reader can check. A "reach for it when" list and a sentence on when to
  skip it follow, because a page that only argues for itself is not useful
  for deciding.

## 1.2.0

- **Ship a GitHub Action.** A prerender step someone has to remember stops
  running by the second deploy, which is how this class of tool quietly fails
  to get adopted. `action.yml` is a composite action mapping every CLI flag to
  an input, with `args` as the escape hatch for anything unmapped.
  - `chrome` defaults to `/usr/bin/google-chrome`, which GitHub's Ubuntu
    runners already have, so puppeteer does not download its own Chromium on
    every run. Verified on a runner: the default resolved and the capture used
    it.
  - `fail-on-empty` defaults on. A build that shipped an empty canvas passing
    green is worse than one that failed.
  - `activate: false` skips the pub.dev install for callers that already put
    the executable on PATH: pinning a git ref, or testing an unreleased build.
- **A CI job that proves it runs**, rather than trusting that the script is
  correct. It builds the Flutter example in this repository and runs the action
  against it with `activate: false`, so the code under test is the checkout and
  not the last release, then asserts the output. On the first run:
  `Prerendered 1 route(s): / 7 nodes, 2191 bytes [parity ok]`, with a sitemap.
- No library or CLI change.

## 1.1.0

Two ways this produced wrong output on a completely standard app, both found by
running it against a fresh `go_router` project rather than by reading the code.

### The generated page kept nothing from your build

Prerendering replaces the document a visitor receives, and the generator wrote a
fresh `<head>` from scratch. Everything `flutter build web` had put there was
dropped: the PWA manifest, the favicon, the theme colour, and most
consequentially `<base href>`.

Without that base href, `flutter_bootstrap.js` resolves `main.dart.js` against
the deep route it was served from, so `/beans/kenya` asked for
`/beans/kenya/main.dart.js`, got a 404, and the Flutter app never booted. The
visitor was left on the static snapshot forever. Nothing in the output looked
wrong, which is why it survived a release.

The build's own head is now carried into every generated page. Tags the tool
computes per route (title, description, canonical, Open Graph, Twitter, JSON-LD)
still win; charset and viewport are not duplicated; inline scripts are dropped,
because a build's service-worker bootstrap re-registers against the wrong scope
from a deep route. An explicit `baseHref` in your config still overrides
everything.

### Every route could come out as a copy of the home page, and the run passed

Flutter web defaults to the hash URL strategy, where the route lives after a `#`
that no server and no crawler ever sees. Prerendering an app in that state gives
you N byte-identical files. The tool warned per route, said "the app may not be
routing on the path", and exited `0`. CI went green and you deployed four
pages that each claim to be different.

- The warning now names the cause and the fix: call `usePathUrlStrategy()`.
- When *every* non-root route collapses onto the root, that is not a warning any
  more. It exits `4` and writes nothing you would have had to un-deploy. One
  duplicate among several is still just a warning, because two paths really can
  render the same page.

### Also

- The README now says to install with `dart pub global activate`, and measures
  what `flutter pub add` costs instead: 24 packages resolved into your app's
  runtime dependencies for a build-time tool.
- It also says the first run downloads about 150 MB of Chromium and takes
  minutes, and suggests caching it in CI.
- New: `SourceHead`, exported, if you drive the engine yourself.

## 1.0.0

First stable release. From here the public API follows semantic versioning: a
breaking change will not land without a major-version bump.

- Seal the 20 leaf classes that make up the public surface (`PrerenderConfig`,
  `PrerenderResult`, `RouteSpec`, the exception types, and the rest) with
  `final`. They are meant to be constructed and read rather than extended, and
  nothing in the package or its tests subtypes them. This keeps the rest of 1.x
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
  reachable from a plain routes file or a YAML config as well as from
  `--crawl`, and had been present since 0.1.0. `normalizeRoute` now rejects both shapes;
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
  the configured route list, which includes a crawl's discovered pages. For a
  fixed route list the output is the same as before.

## 0.2.2

- Shorten the screenshot description. pub.dev accepts up to 200 characters but
  scores only those under 160. The previous release published cleanly and
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
