# Agent notes

This is a command-line tool. Do not add `flutter_prerender` to an app's
`dependencies` or `dev_dependencies`, and do not `import` it. Activate it
globally and run the `flutter_prerender` executable against a web build.

## What it is

The tool loads each route of a `flutter build web` output in headless Chrome,
enables Flutter's accessibility tree, and writes one static HTML file per
route (real `<h1>`/`<p>`/`<a>`, title, meta, Open Graph, optional JSON-LD
and `sitemap.xml`). By default visitors with JavaScript still boot the
original app; crawlers that never run it read the static markup. Turning off
`appScript` / passing `--no-app-script` produces a static-only document.

It does not prerender from Dart sources, does not capture content behind
login, a tap, or a scroll, does not re-snapshot live data, and does not copy
JS/wasm into `--out`. Serve that directory alongside `build/web`, not instead
of it. The app does not need to call `ensureSemantics()`.

## Invocation

    dart pub global activate flutter_prerender
    flutter build web
    flutter_prerender --build-dir build/web --routes routes.txt \
      --out build/prerendered --base-url https://example.com

`routes.txt` is one path per line (`/`, `/about`); `#` comments and blanks
are ignored. Config-file form, from the README and `example/`:

    flutter_prerender -c flutter_prerender.yaml

If `flutter_prerender.yaml` is in the working directory it is loaded
automatically (`defaultConfigFile`). CLI flags override the file. From this
checkout use `dart run flutter_prerender …` instead of the global executable.
`--crawl` starts from the listed routes (or `/` if none) and follows in-page
links. `--chrome` is an existing Chrome binary; otherwise puppeteer downloads
Chromium on first use. `--dry-run` prints the plan and does not launch a
browser.

## Contracts

**Build directory.** `runCli` requires `config.buildDir` (default
`build/web`) to exist and contain `index.html`. Otherwise
`BuildNotFoundException`, exit 1. `StaticServer` serves that directory to
the browser; unknown paths fall back to `index.html`. Output is
`--out`/`outDir` (default `build/prerendered`): `/` → `index.html`,
`/about` → `about/index.html`. The engine creates the output directory but
does not empty it; remove or replace stale route files as part of deployment.
`--dry-run` still requires routes (unless `--crawl` is set), but it does not
require the build to exist and does not launch Chrome.

**Source head.** The CLI parses the built `index.html` with `SourceHead`.
Generated per-route SEO wins, while the build's base href, manifest, icons,
theme metadata, styles and other non-generated head elements are carried into
each page. Inline scripts are deliberately dropped. If calling
`PrerenderEngine` directly, pass a parsed `SourceHead` yourself or those build
head elements are not preserved.

**Browser.** Capture is `PuppeteerCapturer`. No Chrome →
`BrowserLaunchException`, exit 1. Pass `--chrome`. `runCli` closes both the
capturer and its temporary `StaticServer` in a `finally`; direct API callers
own the resources they create and must close them. `PuppeteerCapturer.capture`
closes each page, but the browser stays alive until `close()`.

**Route discovery.** Without `--crawl`, only named routes run. Sources:
`--routes` / `parseRoutesFile` (paths only, not absolute URLs); YAML
`routes:` (strings or `{path, title, …}` maps); `--crawl` then
`discoverRoutes` / `sameOriginRoute` from recovered `<a href>`, capped by
`--max-pages` (default 100). Off-site, `mailto:`, `tel:`, and bare
`#fragment` links are dropped. A route with no inbound link still has to be
listed. Empty routes and no `--crawl` → `ConfigException`, exit 1.

**Exit codes** (`runCli`): 0 success / `--help` / `--version` / valid
`--dry-run`; 1 `PrerenderException` (config, missing build, browser launch);
2 `--fail-on-parity` and `hasParityWarnings`; 3 `--fail-on-empty` and
(`hasEmptyRoutes` or `hasFailedRoutes`); 4 `collapsedOntoRoot`; 64 CLI parser
failure, including an unknown flag. Checks after rendering are ordered 4, 2,
3, so collapse wins if more than one condition is true.

**`--fail-on-empty`.** This is the CI gate. `PrerenderConfig.failOnEmpty`
defaults false, so an empty or failed route still exits 0. The flag fails
when any route recovered zero content nodes (`RouteResult.isEmpty` →
`hasEmptyRoutes`) **or** capture threw `RouteCaptureException`
(`hasFailedRoutes`). It does not gate on parity; that is `--fail-on-parity`
/ `hasParityWarnings` (exit 2). `ParityGuard` flags injected words, not
missing canvas coverage.

**Hash URLs.** Flutter web's default hash strategy makes every path the same
page. The tool writes the files and exits 4 (`collapsedOntoRoot`). Call
`usePathUrlStrategy()` in `main()`, rebuild.

**`robots.txt`.** `--robots` / `generateRobots` is off by default and never
replaces an existing `robots.txt` in the output. Sitemap write needs
`--base-url`; default `generateSitemap` is true. The sitemap contains the
routes actually written, including crawl discoveries, and omits failed
captures. With no successful route, or no base URL, no sitemap is written.

**Direct library use.** `lib/flutter_prerender.dart` exports the whole
pipeline, but it is for a separate build script or tooling package, not an
import inside the Flutter app. `PrerenderEngine.run` neither checks for a web
build nor starts/closes a server or capturer; those conveniences belong to
`runCli`. Capture failures represented by `RouteCaptureException` are recorded
in `PrerenderResult.failedRoutes` and do not abort the remaining queue.

## Mistakes

- **Running against sources (`lib/`, `web/`) instead of a build.** Symptom:
  `Error: No Flutter web build at "…"`, exit 1. Fix: `flutter build web`,
  then `--build-dir build/web` (the directory that contains `index.html`).
- **Expecting body text from a route that renders nothing.** Symptom:
  `[empty: no content recovered]`; with `--fail-on-empty`, exit 3. Capture
  throws `RouteCaptureException` if the Flutter view never boots. Fix: the
  route must paint text on anonymous first load. Annotate
  `Semantics(headingLevel:)`, `Link`, `Semantics(image:)` for real headings,
  anchors, and alt text; unannotated `Text` is recovered as a `<p>`. Content
  behind auth or a tap is not captured.
- **Adding this package to the app.** Symptom: puppeteer in the app's
  package graph. Fix: `dart pub global activate flutter_prerender`.
- **Assuming crawl is on.** Symptom: only listed routes exist under `--out`.
  Fix: pass `--crawl` or list every path.
- **Deploying `--out` without `build/web`.** Symptom: JS/wasm 404. Overlay
  prerendered HTML onto the web build. Firebase Hosting, Netlify, and
  Cloudflare Pages configs: `doc/serving.md`.
- **Reusing a dirty output directory.** Symptom: a route removed from config
  is still deployable, or an old sitemap/robots file survives. The engine
  overwrites files it generates in this run; it does not reconcile or delete
  files from an earlier run.
- **Routes as `https://…`.** Symptom: `ConfigException`, exit 1. Paths only.

## Layout

- `bin/flutter_prerender.dart` — `main` → `runCli`
- `lib/src/cli.dart` — parser, config merge, exit codes
- `lib/src/engine.dart` — `PrerenderEngine`
- `lib/src/browser.dart` — `PuppeteerCapturer`
- `lib/src/config.dart` — `PrerenderConfig`, `RouteSpec`
- `lib/src/routes.dart` — `parseRoutesFile`, `discoverRoutes`, `sameOriginRoute`
- `lib/src/semantics_extractor.dart`, `html_builder.dart`, `parity.dart`,
  `sitemap.dart`, `robots.dart`, `static_server.dart`, `source_head.dart`,
  `exceptions.dart`
- `example/` — sample app, `flutter_prerender.yaml`, `routes.txt`
- `doc/serving.md` — Firebase Hosting, Netlify, Cloudflare Pages
- `action.yml` — composite Action (same flag names as the CLI)
- `tool/measure_crawler_fetch.dart` — serves and fetches the before/after
  example documents without JavaScript; exit 69 if either input is missing,
  exit 1 if required prerendered content is absent
- `tool/crawler_view_figure.dart` — redraws the committed comparison figure
- `test/` — unit tests; `test/e2e_test.dart` is tagged `e2e`

Tests, from the repo root (example is a Flutter app; skip it):

    dart pub get
    dart format .
    dart analyze
    dart test --exclude-tags e2e

e2e needs Chrome and a built example: `cd example && flutter build web`,
then `dart test --tags e2e`.

Example without a build, from the repo root:

    dart run example/what_a_crawler_sees.dart

Falls back to `example/web/index.html` and
`example/expected_output/index.html` when `example/build/` is absent.

The HTTP measurement does not fall back; build and prerender first:

    cd example && flutter build web
    cd ..
    dart run flutter_prerender \
      --config example/flutter_prerender.yaml \
      --build-dir example/build/web \
      --out example/build/prerendered
    dart run tool/measure_crawler_fetch.dart

To prerender the example from this checkout:

    cd example && flutter build web
    cd ..
    dart run flutter_prerender \
      --config example/flutter_prerender.yaml \
      --build-dir example/build/web \
      --out example/build/prerendered

## Contributing

Before changing this repository, read [CONTRIBUTING.md](CONTRIBUTING.md), [package engineering rules](docs/engineering/package.md), and the [debt register](docs/engineering/debt.json). These requirements apply to every contributor. The usage guidance above remains the consumer contract.
