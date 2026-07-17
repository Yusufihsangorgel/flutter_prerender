# flutter_prerender

Prerender a Flutter web app to static, crawlable HTML for SEO.

`flutter_prerender` loads each route of a `flutter build web` output in headless
Chrome, enables Flutter's accessibility tree, and writes a static HTML document
per route: real `<h1>`/`<p>`/`<a>`, plus `<title>`, meta description, Open
Graph, Twitter Card, optional JSON-LD, and a `sitemap.xml`. The generated page
also loads the original app, so a visitor with JavaScript still gets the full
Flutter experience while a crawler reads the static content.

This is the [server-side prerendering that Google Search recommends for
canvas/WebGL content][google-webgl], applied to Flutter web as a build step.

## Why this is needed

A default Flutter web build draws its UI to a canvas. The DOM contains no
readable text, so crawlers that do not run the app see nothing:

- **Googlebot does not support WebGL.** Google's own guidance is to
  "use server-side rendering to prerender ... [which] makes your content
  accessible to everyone, including Googlebot." ([Google Search][google-webgl])
- **Googlebot fetches at most 2 MB per resource** and ignores the rest. A
  default CanvasKit build ships `canvaskit.wasm` well above that limit even
  after Brotli, so the app may never boot for the crawler at all.
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

## Content parity and cloaking

Serving crawlers content a user cannot see is cloaking, and search engines
penalise it. `flutter_prerender` builds the static HTML from the same
accessibility tree the app renders, and after each page it runs a parity guard:
it compares the generated body text with the text the app actually rendered and
warns when the generated page contains words the user never sees. Pass
`--fail-on-parity` to make that a hard error in CI.

Keep the content faithful and this stays within Google's guidance, which draws
the line at "completely different" content and explicitly endorses prerendering
canvas/WebGL. Use the guard, and do not hand-inject keywords into the output.

## Limits

This is a v0.1 with a deliberately narrow scope. Known limits:

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

Tested on Flutter 3.x web (CanvasKit and skwasm renderers). The behaviour
depends on Flutter's semantics DOM, which has been stable across recent 3.x
releases; it is not pinned to a specific build.

## License

MIT. See [LICENSE](LICENSE).

[google-webgl]: https://developers.google.com/search/docs/crawling-indexing/javascript/fix-search-javascript
[flutter-faq]: https://docs.flutter.dev/platform-integration/web/faq
