// Block Pact – short-lived TURN credentials for WebRTC.
//
// Players behind strict NATs (some mobile networks, company Wi-Fi) cannot
// connect peer-to-peer with STUN alone; a TURN server relays their traffic.
// This function asks Cloudflare's TURN service for credentials that expire
// after a day, so no TURN secret ever ships with the game.
//
// Setup (once): Cloudflare dashboard → Realtime → TURN → create a TURN key,
// then in Supabase → Edge Functions → Secrets add
//   CF_TURN_KEY_ID        the key id
//   CF_TURN_KEY_API_TOKEN the key's API token
// Without them the function returns no servers and the game keeps using STUN.

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
const TTL_SECONDS = 86400;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const keyId = Deno.env.get("CF_TURN_KEY_ID") ?? "";
  const token = Deno.env.get("CF_TURN_KEY_API_TOKEN") ?? "";
  if (!keyId || !token) return json({ iceServers: [], ttl: 0, configured: false });

  const res = await fetch(
    `https://rtc.live.cloudflare.com/v1/turn/keys/${keyId}/credentials/generate-ice-servers`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ ttl: TTL_SECONDS }),
    },
  );
  if (!res.ok) {
    console.error("cloudflare turn", res.status, await res.text());
    return json({ iceServers: [], ttl: 0, configured: true, error: "upstream" }, 502);
  }
  const data = await res.json();
  const servers = (Array.isArray(data.iceServers) ? data.iceServers : [data.iceServers])
    .filter((s: { urls?: unknown }) => s && s.urls)
    .map((s: { urls: string | string[]; username?: string; credential?: string }) => ({
      ...s,
      // Port 53 often times out in browsers.
      urls: (Array.isArray(s.urls) ? s.urls : [s.urls]).filter((u) => !u.includes(":53")),
    }))
    .filter((s: { urls: string[] }) => s.urls.length > 0);
  return json({ iceServers: servers, ttl: TTL_SECONDS, configured: true });
});
