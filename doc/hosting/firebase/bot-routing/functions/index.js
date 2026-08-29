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
