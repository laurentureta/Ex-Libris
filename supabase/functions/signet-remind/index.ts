// Signet : rappels de lecture. Appelée toutes les 15 minutes par pg_cron ; envoie un Web Push (sans contenu)
// aux appareils dont c'est l'heure. Le texte de la notification est composé par l'appli elle-même (service worker).
const URL_ = Deno.env.get('SUPABASE_URL')!;
const KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SUB = 'https://laurentureta.github.io/Ex-Libris/';
const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' };

const b64u = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const enc = (s: string) => new TextEncoder().encode(s);

async function rpc(fn: string, args: Record<string, unknown> = {}) {
  const r = await fetch(`${URL_}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args),
  });
  if (!r.ok) throw new Error(`${fn} ${r.status} ${await r.text()}`);
  return r.json();
}

let cache: { cfg: Record<string, string>; priv: CryptoKey } | null = null;
async function keys() {
  if (cache) return cache;
  let cfg = await rpc('signet_config_get') as Record<string, string>;
  if (!cfg.vapid_jwk || !cfg.vapid_pub) {
    const kp = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
    const jwk = await crypto.subtle.exportKey('jwk', kp.privateKey);
    const raw = new Uint8Array(await crypto.subtle.exportKey('raw', kp.publicKey));
    await rpc('signet_config_set', { k: 'vapid_jwk', v: JSON.stringify(jwk) });
    await rpc('signet_config_set', { k: 'vapid_pub', v: b64u(raw) });
    cfg = await rpc('signet_config_get');
  }
  const priv = await crypto.subtle.importKey('jwk', JSON.parse(cfg.vapid_jwk), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  cache = { cfg, priv };
  return cache;
}

async function vapid(aud: string, priv: CryptoKey) {
  const h = b64u(enc(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const p = b64u(enc(JSON.stringify({ aud, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: SUB })));
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, priv, enc(`${h}.${p}`)));
  return `${h}.${p}.${b64u(sig)}`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  try {
    const { cfg, priv } = await keys();
    if (req.method === 'GET') return Response.json({ pub: cfg.vapid_pub }, { headers: cors });
    if (!cfg.cron || req.headers.get('x-signet-cron') !== cfg.cron) return new Response('forbidden', { status: 403, headers: cors });
    const due = await rpc('signet_push_take') as string[];
    let ok = 0, gone = 0, fail = 0;
    const tokens = new Map<string, string>();
    await Promise.all(due.map(async (endpoint) => {
      try {
        const aud = new URL(endpoint).origin;
        if (!tokens.has(aud)) tokens.set(aud, await vapid(aud, priv));
        const r = await fetch(endpoint, {
          method: 'POST',
          headers: { TTL: '43200', Urgency: 'normal', Authorization: `vapid t=${tokens.get(aud)}, k=${cfg.vapid_pub}`, 'Content-Length': '0' },
        });
        if (r.status === 404 || r.status === 410) { gone++; await rpc('signet_push_gone', { e: endpoint }).catch(() => {}); }
        else if (r.ok) ok++; else fail++;
      } catch (_) { fail++; }
    }));
    return Response.json({ due: due.length, ok, gone, fail }, { headers: cors });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500, headers: cors });
  }
});
