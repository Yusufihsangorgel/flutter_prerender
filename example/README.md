# flutter_prerender example

A minimal Flutter web app (`lib/main.dart`) plus a prerender configuration
(`flutter_prerender.yaml`), used to demonstrate `flutter_prerender` end to end.

The app is deliberately *stock*: it never calls `ensureSemantics()`. The tool
enables Flutter's accessibility tree from the outside, so no app source changes
are needed. The widgets are annotated with `Semantics(headingLevel:)`, `Link`
and `Semantics(image:)`, which is what lets the recovered document contain a
real `<h1>`, a real `<a href>` and image alt text.

## Run it

```sh
flutter build web
dart run flutter_prerender -c flutter_prerender.yaml
```

Prerendered HTML is written to `build/prerendered/`:

```
build/prerendered/
  index.html      # the "/" route, crawlable
  sitemap.xml
```

## Expected output

`expected_output/index.html` in this directory is a checked-in sample of what
the `/` route produces, so you can see the result without a local build. Real
output will differ slightly with the Flutter version used to build the app.
