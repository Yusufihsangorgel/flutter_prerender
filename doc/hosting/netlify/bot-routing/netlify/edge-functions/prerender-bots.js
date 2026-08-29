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
