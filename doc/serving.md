# Serving the prerendered output

`flutter_prerender` writes one HTML file per route (`/` → `index.html`,
`/about` → `about/index.html`) plus `sitemap.xml`. It does not copy the
JavaScript or wasm. A crawler sees that HTML only if the host returns it for
the path the crawler requested. Getting the rewrite rules wrong is how a
correct prerender still looks empty in Search Console.

Two topologies. They are not equivalent. Pick one.

Copy-pasteable files for each host live under [`doc/hosting/`](hosting/).

## Overlay, or bot routing

**Overlay.** Copy the prerendered HTML over the Flutter web build and serve
that directory. Every client — Googlebot, Slack's unfurler, a phone — receives
the same document. That document already loads `/flutter_bootstrap.js` and
removes `#flutter-prerender-content` once Flutter paints, so a visitor with
JavaScript still boots the app.

What that costs: the visitor downloads the static markup as well as the app
(small, one extra `<div>` of the first paint). There can be a flash of that
markup before Flutter replaces it. The snapshot is frozen at build time, so a
client that never runs JavaScript sees Tuesday's roast list even if the app
would have fetched Wednesday's. That is the same snapshot a crawler sees,
which is the point.

**Bot routing.** Look at `User-Agent` and hand crawlers the prerendered file
while humans get the original `flutter build web` shell. This is what Google
calls [dynamic rendering][google-dynamic-rendering]: a workaround, not a
recommendation, "because it creates additional complexities and resource
requirements."

What that costs:

- The list of crawlers is a moving target. A bot you did not name gets the
  empty canvas. A browser that spoofs `Googlebot` gets the snapshot. New
  preview fetchers (a chat app, an AI crawler) appear without notice.
- Google's [spam policies][google-cloaking] call it cloaking to present
  different content to users and search engines with intent to manipulate
  rankings, including "inserting text or keywords into a page only when the
  user agent that is requesting the page is a search engine." Dynamic
  rendering is [not cloaking when the two versions are similar][google-dynamic-rendering];
  it is cloaking when they are not ("a page about cats to users and a page
  about dogs to crawlers"). The parity guard in this tool is how you stay on
  the similar side. It cannot see a hand-edited bot-only file.
- Every HTML request that is classified as a bot runs extra code (a Cloud
  Function, an Edge Function, a Pages Function). Assets must be excluded or
  you pay for `/main.dart.js`. CDNs must `Vary: User-Agent` or they will
  cache the bot page for a human, or the reverse.

Google's own JavaScript guidance still says
[server-side or pre-rendering is a great idea][google-js-seo] because not
every bot runs JavaScript. Overlay does that without sniffing. Reach for bot
routing when you have a concrete reason humans must not receive the snapshot
(you measured a flash you cannot live with, or a policy that forbids serving
the static markup to browsers). Do not reach for it because it feels more
"SEO."

None of Firebase Hosting, Netlify, or Cloudflare Pages can branch on
`User-Agent` in their static rewrite file. Bot routing on all three is a
function that inspects the header. Overlay is the rewrite file alone.

The deploy directory in every snippet is `deploy/`. Assemble overlay with:

```sh
mkdir -p deploy
cp -r build/web/. deploy/
cp -r build/prerendered/. deploy/
```

The second copy overwrites `index.html` (and every other prerendered route)
and drops `sitemap.xml` at the root. Serve `deploy/`, not `build/prerendered/`
and not `build/web/` on its own.

## Firebase Hosting

Configuration lives in `firebase.json`.
[Rewrites][firebase-rewrites] match a URL path and either serve a local file
or send the request to a Cloud Function. There is no request-header
condition. [Priority][firebase-priority] is: reserved `/__/*` paths,
redirects, **exact-match static content**, then rewrites. A rewrite runs only
when no file or directory exists at that path.

### Overlay

[`doc/hosting/firebase/overlay/firebase.json`](hosting/firebase/overlay/firebase.json)

```json
{
  "hosting": {
    "public": "deploy",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "trailingSlash": false,
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ]
  }
}
```

`trailingSlash: false` makes Hosting [redirect away a trailing slash][firebase-slash]
so Flutter's path URLs (`/about`, not `/about/`) stay canonical. Unspecified,
Hosting keeps the slash on directory indexes (`about/index.html`). The
catch-all rewrite is the [SPA fallback][firebase-rewrites]: it fires only for
paths that are not a real file, so `/about` still serves
`about/index.html` from the overlay and `/not-a-route` still boots the app.

Deploy with `firebase deploy --only hosting`.

### Bot routing

Because exact-match static content beats rewrites, a `public/index.html` is
always served for `/` and a function never sees that request. Bot routing
therefore **must not** leave HTML at the route paths. Move the SPA shell and
the prerendered tree aside, leave JS/wasm/assets at the URL the app requests,
and send every missing path to a function:

```sh
mkdir -p deploy
cp -r build/web/. deploy/
mkdir -p deploy/__spa
mv deploy/index.html deploy/__spa/index.html
mkdir -p deploy/__prerendered
cp -r build/prerendered/. deploy/__prerendered/
# Crawlers request these at the site root, not under __prerendered/.
if [ -f deploy/__prerendered/sitemap.xml ]; then
  mv deploy/__prerendered/sitemap.xml deploy/
fi
if [ -f deploy/__prerendered/robots.txt ]; then
  mv deploy/__prerendered/robots.txt deploy/
fi
```

[`doc/hosting/firebase/bot-routing/firebase.json`](hosting/firebase/bot-routing/firebase.json)

```json
{
  "hosting": {
    "public": "deploy",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "trailingSlash": false,
    "rewrites": [
      {
        "source": "**",
        "function": {
          "functionId": "servePrerender",
          "region": "us-central1",
          "pinTag": true
        }
      }
    ]
  }
}
```

The object form of `function`, including `pinTag`, is what the
[Hosting + Cloud Functions][firebase-functions] page specifies (2nd gen;
`pinTag` keeps the function version pinned to the Hosting release).
`/main.dart.js`, `/__spa/index.html`, `/__prerendered/about/index.html`,
and `/sitemap.xml` are exact matches, so they never enter the function.

[`doc/hosting/firebase/bot-routing/functions/index.js`](hosting/firebase/bot-routing/functions/index.js)
fetches the matching static file from this same Hosting site. Set
`Vary: User-Agent` so the [CDN cache key][firebase-vary] includes the header;
without it, the first visitor's flavour of the page is what the next visitor
gets. Dynamic Hosting content is [not cached unless you set
`Cache-Control`][firebase-cache].

```js
const { onRequest } = require("firebase-functions/v2/https");

// Keep in step with the nginx map in the README. A bot you omit sees the
// empty SPA shell; that is the failure mode of this topology.
const BOT =
  /googlebot|google-inspectiontool|bingbot|duckduckbot|slurp|facebookexternalhit|facebot|twitterbot|linkedinbot|slackbot|discordbot|whatsapp|telegrambot|applebot|yandex|baiduspider|embedly|pinterest|skypeuripreview|vkshare/i;

function prettyDir(prefix, pathname) {
  const trimmed = pathname.replace(/\/+$/, "") || "";
  if (trimmed === "") return `${prefix}/`;
  return `${prefix}${trimmed}/`;
}

exports.servePrerender = onRequest({ region: "us-central1" }, async (req, res) => {
  const ua = req.get("user-agent") || "";
  const host = req.get("x-forwarded-host") || req.get("host");
  const proto = req.get("x-forwarded-proto") || "https";
  const origin = `${proto}://${host}`;

  const target = BOT.test(ua)
    ? prettyDir("/__prerendered", req.path)
    : "/__spa/";

  const upstream = await fetch(new URL(target, origin));
  const fallback =
    !upstream.ok && BOT.test(ua)
      ? await fetch(new URL("/__spa/", origin))
      : upstream;

  res.status(fallback.status);
  res.set("Content-Type", "text/html; charset=utf-8");
  res.set("Vary", "User-Agent");
  res.set("Cache-Control", "public, max-age=300, s-maxage=600");
  res.send(await fallback.text());
});
```

Scaffold the functions directory with `firebase init functions` and replace
`functions/index.js` with that file. Deploy hosting and the function
together: `firebase deploy --only functions,hosting`.

## Netlify

Redirects are declared in `_redirects` or in `netlify.toml`.
[Conditions][netlify-redirects] are country, language, role, and cookie
presence. User-Agent is not one of them; a `_redirects` line that tries
`User-Agent=Googlebot` is ignored. Status `200` is a
[rewrite][netlify-rewrites]. Existing files [shadow][netlify-shadow] a
rewrite unless you force it with `!`.

### Overlay

[`doc/hosting/netlify/overlay/netlify.toml`](hosting/netlify/overlay/netlify.toml)

```toml
[build]
  publish = "deploy"

# History-API fallback for paths the prerender did not write. Shadowing
# keeps /about/index.html in front of this rule.
[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200
```

Pretty URLs are on by default, so `/about` and `/about/` are the same rule.
Put `netlify.toml` at the repository root; the publish directory is `deploy/`
after the overlay copy.

### Bot routing

Assemble the same `__spa` / `__prerendered` layout as Firebase. Then an
[Edge Function][netlify-edge-api] rewrites matching requests to
`/__prerendered/…` by returning a `URL` (Netlify's 200 rewrite). Edge
functions run [before redirects][netlify-edge-order].

Netlify also classifies `User-Agent` into a `Netlify-Agent-Category`
header (`crawler`, `page-preview`, `ai-agent`, `browser`, …) and documents
using it to [return a pre-rendered page][netlify-ua] for clients that do not
run JavaScript. That taxonomy is maintained by Netlify; it is still a
classifier, and `netlify dev` [does not set the header][netlify-ua]. The
function below accepts either the category or the same regex as the other
hosts so a local run still works.

[`doc/hosting/netlify/bot-routing/netlify.toml`](hosting/netlify/bot-routing/netlify.toml)

```toml
[build]
  publish = "deploy"

[[redirects]]
  from = "/*"
  to = "/__spa/index.html"
  status = 200

[[edge_functions]]
  function = "prerender-bots"
  path = "/*"
  excludedPath = [
    "/__prerendered/*",
    "/__spa/*",
    "/assets/*",
    "/canvaskit/*",
    "/icons/*",
    "/flutter.js",
    "/flutter_bootstrap.js",
    "/flutter_service_worker.js",
    "/manifest.json",
    "/favicon.png",
    "/sitemap.xml",
    "/robots.txt",
  ]
```

[`doc/hosting/netlify/bot-routing/netlify/edge-functions/prerender-bots.js`](hosting/netlify/bot-routing/netlify/edge-functions/prerender-bots.js)

```js
const BOT =
  /googlebot|google-inspectiontool|bingbot|duckduckbot|slurp|facebookexternalhit|facebot|twitterbot|linkedinbot|slackbot|discordbot|whatsapp|telegrambot|applebot|yandex|baiduspider|embedly|pinterest|skypeuripreview|vkshare/i;

function prettyDir(prefix, pathname) {
  const trimmed = pathname.replace(/\/+$/, "") || "";
  if (trimmed === "") return `${prefix}/`;
  return `${prefix}${trimmed}/`;
}

export default async (request) => {
  const category = request.headers.get("netlify-agent-category") ?? "";
  const ua = request.headers.get("user-agent") ?? "";
  const isBot =
    /^(crawler|page-preview|ai-agent)(;|$)/.test(category) || BOT.test(ua);
  if (!isBot) return;

  const path = new URL(request.url).pathname;
  return new URL(prettyDir("/__prerendered", path), request.url);
};

export const config = {
  path: "/*",
};
```

Returning `undefined` continues the chain to the SPA rewrite. Returning a
`URL` is an internal rewrite; the address bar does not change. Edge function
source sits next to the repo (`netlify/edge-functions/`), not inside
`deploy/`.

This is not Netlify's post-processing "Prerendering" product. That service
hits a headless browser on their side. These files are the ones
`flutter_prerender` already wrote.

## Cloudflare Pages

[`_redirects`][cf-redirects] is path in, path out. Cloudflare's own advanced
table lists rewrites-by-status other than 200 as unsupported, and
**redirect by country, language, or cookie as unsupported**. There is no
User-Agent condition. Unlike Netlify, [redirects are always followed][cf-redirects],
even when a static file exists at that path. A catch-all
`/* /index.html 200` would hide every prerendered `about/index.html`.

[Route matching][cf-serving]: if an HTML file exists for the path, Pages
serves it (`/about/index.html` is redirected to `/about/`). If there is
**no** top-level `404.html`, Pages treats the project as an SPA and maps
unmatched paths to `/`.

### Overlay

Assemble `deploy/` as above. Set the Pages build output directory to `deploy`.
Do not add a catch-all `_redirects`. Do not add a `404.html` — that would
disable the SPA fallback for routes you did not prerender.

No config file. The host's defaults are the overlay.

### Bot routing

Same `__spa` / `__prerendered` layout. Because a top-level `index.html` would
be the SPA fallback target, keep the shell at `__spa/index.html` and add a
single rewrite so humans land there. That rewrite is the one case a
`_redirects` file is required, and it must not be a blanket `/* /index.html`.

[`doc/hosting/cloudflare/bot-routing/_redirects`](hosting/cloudflare/bot-routing/_redirects):

```
/ /__spa/index.html 200
```

Only `/` is rewritten. `/about` has no HTML file, so the default SPA
behaviour would send it to `/`, which then becomes `__spa/index.html`.
`/__prerendered/about/` is a real file and is left alone.

A [Pages Function middleware][cf-middleware] in `functions/_middleware.js`
runs in front of static files when you want it to. Bots are rewritten with
[`env.ASSETS.fetch()`][cf-assets] to the pretty path (`/users/index.html`
is fetched as `/users/`, not as the file).

[`doc/hosting/cloudflare/bot-routing/functions/_middleware.js`](hosting/cloudflare/bot-routing/functions/_middleware.js)

```js
const BOT =
  /googlebot|google-inspectiontool|bingbot|duckduckbot|slurp|facebookexternalhit|facebot|twitterbot|linkedinbot|slackbot|discordbot|whatsapp|telegrambot|applebot|yandex|baiduspider|embedly|pinterest|skypeuripreview|vkshare/i;

function prettyDir(prefix, pathname) {
  const trimmed = pathname.replace(/\/+$/, "") || "";
  if (trimmed === "") return `${prefix}/`;
  return `${prefix}${trimmed}/`;
}

export async function onRequest(context) {
  const { request, env, next } = context;
  const url = new URL(request.url);

  if (
    /\.(js|mjs|wasm|css|png|jpe?g|svg|json|otf|ttf|woff2?|map)$/i.test(
      url.pathname,
    )
  ) {
    return next();
  }

  const ua = request.headers.get("user-agent") || "";
  if (!BOT.test(ua)) return next();

  const target = new URL(prettyDir("/__prerendered", url.pathname), url);
  const asset = await env.ASSETS.fetch(target);
  if (asset.status === 404) return next();
  return asset;
}
```

On a purely static project Pages does not charge for requests. Adding
Functions makes matching routes invoke the Function.
[`_routes.json`][cf-routes] in the **build output** (`deploy/_routes.json`)
keeps assets on the static path:

[`doc/hosting/cloudflare/bot-routing/_routes.json`](hosting/cloudflare/bot-routing/_routes.json)

```json
{
  "version": 1,
  "include": ["/*"],
  "exclude": [
    "/assets/*",
    "/canvaskit/*",
    "/icons/*",
    "/*.js",
    "/*.mjs",
    "/*.wasm",
    "/manifest.json",
    "/favicon.png",
    "/sitemap.xml",
    "/robots.txt",
    "/__prerendered/*",
    "/__spa/*"
  ]
}
```

`functions/_middleware.js` lives at the **repository root**, not inside
`deploy/`. `_routes.json` and `_redirects` live in `deploy/`. Pages looks
for `/functions` in the project; it looks for `_routes.json` in the output
directory.

## Sources

Fetched 2026-08-29. Formats change; if a snippet here disagrees with the
host, the host wins.

| Host | What was read | Retrieved |
| --- | --- | --- |
| Firebase Hosting | [Configure Hosting behavior][firebase-full] (rewrites, priority, `trailingSlash`), [Cloud Functions][firebase-functions] (`function.functionId` / `pinTag`), [Manage cache][firebase-cache] (`Cache-Control`, `Vary`) | 2026-08-24 UTC on each page |
| Netlify | [Redirects][netlify-redirects] (conditions: country, language, role, cookie), [Redirect options][netlify-options], [Rewrites and proxies][netlify-rewrites] (SPA `/* /index.html 200`, shadowing), [Edge Functions API][netlify-edge-api] (return a `URL` to rewrite), [Declarations][netlify-edge-decl] (`header` matching), [User-Agent categories][netlify-ua] | current docs as of 2026-08-29 |
| Cloudflare Pages | [Redirects][cf-redirects] (no country/language/cookie; always followed), [Serving Pages][cf-serving] (HTML matching, SPA when no `404.html`), [Functions routing][cf-routes] (`_routes.json`), [Middleware][cf-middleware], [API reference][cf-assets] (`env.ASSETS.fetch` pretty paths) | redirects/headers 2026-08-25 UTC; serving/functions 2026-04-21 UTC |
| Google Search | [Dynamic rendering as a workaround][google-dynamic-rendering], [Spam policies: cloaking][google-cloaking], [JavaScript SEO basics][google-js-seo] | dynamic rendering 2025-12-10 UTC; spam policies 2026-08-28 UTC |

[firebase-full]: https://firebase.google.com/docs/hosting/full-config
[firebase-rewrites]: https://firebase.google.com/docs/hosting/full-config#rewrites
[firebase-priority]: https://firebase.google.com/docs/hosting/full-config#hosting_priority_order
[firebase-slash]: https://firebase.google.com/docs/hosting/full-config#trailing-slashes
[firebase-functions]: https://firebase.google.com/docs/hosting/functions
[firebase-cache]: https://firebase.google.com/docs/hosting/manage-cache
[firebase-vary]: https://firebase.google.com/docs/hosting/manage-cache#vary_headers
[netlify-redirects]: https://docs.netlify.com/manage/routing/redirects/overview/
[netlify-options]: https://docs.netlify.com/manage/routing/redirects/redirect-options/
[netlify-rewrites]: https://docs.netlify.com/manage/routing/redirects/rewrites-proxies/
[netlify-shadow]: https://docs.netlify.com/manage/routing/redirects/rewrites-proxies/#shadowing
[netlify-edge-api]: https://docs.netlify.com/build/edge-functions/api/
[netlify-edge-decl]: https://docs.netlify.com/build/edge-functions/declarations/
[netlify-edge-order]: https://docs.netlify.com/manage/routing/redirects/overview/#rule-processing-order
[netlify-ua]: https://docs.netlify.com/build/user-agent-categories/
[cf-redirects]: https://developers.cloudflare.com/pages/configuration/redirects/
[cf-serving]: https://developers.cloudflare.com/pages/configuration/serving-pages/
[cf-routes]: https://developers.cloudflare.com/pages/functions/routing/
[cf-middleware]: https://developers.cloudflare.com/pages/functions/middleware/
[cf-assets]: https://developers.cloudflare.com/pages/functions/api-reference/
[google-dynamic-rendering]: https://developers.google.com/search/docs/crawling-indexing/javascript/dynamic-rendering
[google-cloaking]: https://developers.google.com/search/docs/essentials/spam-policies#cloaking
[google-js-seo]: https://developers.google.com/search/docs/crawling-indexing/javascript/javascript-seo-basics
