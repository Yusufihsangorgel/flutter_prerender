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
