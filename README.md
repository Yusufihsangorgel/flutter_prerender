# flutter_prerender

![flutter_prerender banner](https://raw.githubusercontent.com/Yusufihsangorgel/flutter_prerender/main/doc/banner.png)

Prerender a Flutter web app to static, crawlable HTML for SEO.

It is a **command-line tool**: you run it against a `flutter build web` output on
your machine or in CI. It is not a package you add to your app's dependencies, so
pub.dev lists it under the platforms it *runs* on (Linux, macOS, Windows), not the
web app it targets.

`flutter_prerender` loads each route of a `flutter build web` output in headless
Chrome, enables Flutter's accessibility tree, and writes a static HTML document
per route: real `<h1>`/`<p>`/`<a>`, plus `<title>`, meta description, Open
Graph, Twitter Card, optional JSON-LD, and a `sitemap.xml`. The generated page
also loads the original app, so a visitor with JavaScript still gets the full
Flutter experience while a crawler reads the static content.

This is the [server-side prerendering that Google Search recommends for
canvas/WebGL content][google-webgl], applied to Flutter web as a build step.

![Diagram of the flutter_prerender build pipeline and the two serving topologies: bot routing by user agent, and overlay with hydration](https://raw.githubusercontent.com/Yusufihsangorgel/flutter_prerender/main/doc/architecture.png)

## Why this is needed

A default Flutter web build draws its UI to a canvas. The DOM contains no
readable text, so crawlers that do not run the app see nothing:

- **Googlebot does not support WebGL.** Google's own guidance is to
  "use server-side rendering to prerender ... [which] makes your content
  accessible to everyone, including Googlebot." ([Google Search][google-webgl])
- **A default CanvasKit build is heavy.** It ships `canvaskit.wasm` at several
  megabytes even after Brotli. Google warns that large or slow resources can be
  skipped during rendering, so the app may never boot for the crawler at all.
- **Crawlers that never run JavaScript** (Facebook, X/Twitter, LinkedIn and
  Slack link unfurlers) only read `index.html`.

Runtime SEO packages inject tags after the app boots, so they inherit all three
problems. Building the HTML ahead of time does not.

Flutter's own FAQ recommends [Jaspr or plain HTML][flutter-faq] for text-rich,
document-like sites. That is good advice for a greenfield content site. This
tool is for the other case: you already have a Flutter web app and want its
existing routes indexable without a rewrite.

## Install

```sh
dart pub global activate flutter_prerender
```

Or add it as a dev dependency and run it with `dart run`.

The tool drives Chrome through `package:puppeteer`. It will download a private
Chromium on first use, or you can point it at an existing browser with
`--chrome`.

## Use

```sh
flutter build web
dart run flutter_prerender --build-dir build/web --routes routes.txt \
  --out build/prerendered --base-url https://example.com
```

`routes.txt` is one route per line:

```
/
/about
/beans/kenya
```

Or drive everything from a config file (`flutter_prerender.yaml`), which also
carries per-route metadata:

```yaml
buildDir: build/web
out: build/prerendered
baseUrl: https://example.com
routes:
  - path: /
    title: Zebrafish Coffee Roasters
    description: Small-batch arabica roasted every Tuesday.
    jsonLd:
      "@context": https://schema.org
      "@type": Organization
      name: Zebrafish Coffee Roasters
  - /about
```

```sh
dart run flutter_prerender -c flutter_prerender.yaml
```

CLI flags override the config file. See `flutter_prerender --help` for the full
list. A full example lives in [`example/`](example/).

## Crawling

Listing every route by hand does not scale. Pass `--crawl` and the tool starts
from your routes (or `/` if you give none), then follows the in-page links it
already recovers from each page. Every same-origin link is normalised and
prerendered if it has not been seen yet:

```sh
dart run flutter_prerender --build-dir build/web --crawl \
  --out build/prerendered --base-url https://example.com
```

`--max-pages` bounds the run (default 100). Off-site links, `mailto:`/`tel:`
links, and bare `#fragment` links are skipped. An absolute URL is followed only
when its origin matches `--base-url`; relative links are always in scope. The
crawl only finds pages you can reach by clicking, so a route with no link
pointing at it still needs to be listed. Without `--crawl` the tool prerenders
exactly the routes you name and nothing else.

## robots.txt

A sitemap nothing points at is half the job. Pass `--robots` and a `robots.txt`
is written next to the sitemap, declaring it:

```sh
dart run flutter_prerender --base-url https://example.com --sitemap --robots
```

```
User-agent: *
Allow: /

Sitemap: https://example.com/sitemap.xml
```

It is off by default and never replaces a `robots.txt` that is already in the
output. A project that ships `web/robots.txt` has it copied into the build, and
overwriting somebody's crawl rules would be a worse bug than not writing the
file at all; the existing one is left alone and the run reports it. The
`Sitemap:` line only appears when a sitemap was actually produced, so crawlers
are never sent to a URL that would 404.

## Serving the output

`build/prerendered/` holds one `index.html` per route plus `sitemap.xml`. It
does not contain the app's JavaScript and wasm assets, so serve it alongside
`build/web`, not instead of it. Two common topologies:

**Overlay.** Lay the prerendered HTML over the build so each route's
`index.html` is the crawlable one and every other asset comes from `build/web`:

```sh
cp -r build/web/. deploy/
cp -r build/prerendered/. deploy/
```

Visitors with JavaScript boot the app from that same page (the generated HTML
loads `/flutter_bootstrap.js` and removes the static fallback once the app is
up); crawlers read the static content. This is why the default bootstrap `src`
is the absolute `/flutter_bootstrap.js`; a relative path would 404 on a deep
route like `/beans/kenya`.

**Bot routing.** Serve the SPA to humans and the prerendered HTML to crawlers,
keyed on the user agent. For nginx:

```nginx
map $http_user_agent $is_bot {
  default 0;
  ~*(googlebot|bingbot|duckduckbot|slurp|facebookexternalhit|twitterbot|linkedinbot|slackbot) 1;
}

server {
  root /srv/build/web;

  location / {
    if ($is_bot) {
      rewrite ^/(.*)$ /prerendered/$1/index.html last;
    }
    try_files $uri $uri/ /index.html;   # SPA fallback for humans
  }

  location /prerendered/ {
    internal;
    alias /srv/build/prerendered/;
  }
}
```

## Getting good output

The recovered structure is only as good as the app's semantics. An unannotated
`Text('Title', style: TextStyle(fontSize: 32))` looks like a heading to a human
but is recovered as a paragraph. To get real headings, links and image alt
text, annotate the widgets you care about:

```dart
Semantics(headingLevel: 1, child: Text('Page title'));
Link(uri: Uri.parse('/next'), builder: ...);          // -> <a href>
Semantics(image: true, label: 'Alt text', child: ...); // -> <img alt>
```

The app does not need to call `ensureSemantics()`. The tool turns the
accessibility tree on from the outside, so no app source change is required.

## Content parity

After building each page, `flutter_prerender` runs a parity guard. It compares
the generated HTML against Flutter's own accessibility text (the only
machine-readable text the engine exposes) and flags words in the output that are
not in that text, so it catches extractor drift and hand-edited output. It
cannot verify the painted canvas, since there is no separate visible-text source
to compare against. Image alt text is exempt, because it comes from an
aria-label rather than visible body text. Pass `--fail-on-parity` to turn a flag
into a hard CI error.

Keep the recovered content faithful and do not hand-inject keywords. Serving
crawlers content a user cannot see is cloaking, and search engines penalise it.
Google endorses prerendering canvas/WebGL as long as the content is not
"completely different", so a faithful prerender stays within its guidance.

## Limits

The scope is deliberately narrow. Known limits:

- **Static snapshot.** Output reflects the app at build time. Content that
  changes at runtime (live data, per-user views) is not re-prerendered until
  you run the tool again.
- **No content behind auth or interaction.** The tool loads each route as an
  anonymous first paint. Anything gated behind login, a tap, or a scroll is not
  captured.
- **Multi-route needs URL routing.** Each route is loaded as its own URL, so
  the app must resolve content from the path (deep linking). Routes reachable
  only by in-app navigation are not captured.
- **Order follows the semantics tree**, not on-screen geometry, so unusual
  layouts can reorder blocks.
- **Requires Chrome** at prerender time (not at app runtime).

## Compatibility

Developed and tested against Flutter 3.41.2 (web, both the CanvasKit and skwasm
renderers). Later 3.x releases were not exercised in this version.

Flutter's semantics DOM is an engine-internal contract, not a public API. After
a Flutter upgrade, re-verify: run the tool on your build and confirm the output
still contains your headings and links. The `--fail-on-empty` flag makes a
silent regression (no content recovered) a hard error in CI.

## License

MIT. See [LICENSE](LICENSE).

[google-webgl]: https://developers.google.com/search/docs/crawling-indexing/javascript/fix-search-javascript
[flutter-faq]: https://docs.flutter.dev/platform-integration/web/faq
