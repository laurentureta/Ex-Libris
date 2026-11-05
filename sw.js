/* Signet : fonctionnement hors ligne.
   L'app s'ouvre tout de suite depuis le cache, puis se met à jour en arrière-plan. */
const SHELL = 'signet-shell-v5', CDN = 'signet-cdn-v1', IMG = 'signet-img-v1', META = 'signet-meta';
const CORE = ['./', './index.html', './manifest.webmanifest', './icon-180.png', './icon-192.png', './icon-512.png', './three-r170.module.min.js', './edinburgh3d.json'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(SHELL).then(c => Promise.all(CORE.map(u => c.add(new Request(u, {cache:'no-cache'})).catch(() => {})))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(ks => Promise.all(ks.filter(k => k.startsWith('signet-') && ![SHELL, CDN, IMG, META].includes(k)).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

// une nouvelle version vient d'être mise de côté : on le note, l'app le demandera une fois ouverte
async function notifyUpdate(){
  await (await caches.open(META)).put('/__signet_update', new Response(String(Date.now())));
  const cs = await self.clients.matchAll({type:'window', includeUncontrolled:true});
  cs.forEach(c => c.postMessage({type:'signet-update'}));
}
self.addEventListener('message', e => {
  if (!e.data || e.data.type !== 'signet-check') return;
  e.waitUntil((async () => {
    const c = await caches.open(META), r = await c.match('/__signet_update');
    if (r) { await c.delete('/__signet_update'); if (e.source) e.source.postMessage({type:'signet-update'}); }
  })());
});

// Coquille de l'app : réponse immédiate depuis le cache, téléchargement de la nouvelle version en parallèle.
async function shell(e){
  const u = new URL(e.request.url), key = u.pathname.endsWith('/') ? u.pathname + 'index.html' : u.pathname;
  const c = await caches.open(SHELL);
  const hit = await c.match(key), old = hit ? hit.clone() : null;
  const net = fetch(new Request(key, {cache:'no-cache'})).then(async res => {
    if (!res || !res.ok) return res;
    if (hit) {
      const [a, b] = await Promise.all([old.text(), res.clone().text()]);
      if (a !== b) { await c.put(key, res.clone()); await notifyUpdate(); return res; }
    }
    await c.put(key, res.clone());
    return res;
  }).catch(() => null);
  if (hit) { e.waitUntil(net); return hit; }
  const res = await net;
  return res || new Response('<!doctype html><meta charset="utf-8"><title>Signet</title><p style="font:17px -apple-system;padding:40px">Signet a besoin d’une connexion pour son tout premier lancement.</p>', {headers:{'Content-Type':'text/html; charset=utf-8'}});
}

// Bibliothèques externes (lecteur de codes, reconnaissance de texte) : gardées après le premier usage.
async function cacheFirst(cacheName, req, max, opaqueOk){
  const c = await caches.open(cacheName);
  const hit = await c.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res && (res.ok || (opaqueOk && res.type === 'opaque'))) {
    c.put(req, res.clone());
    if (max) c.keys().then(ks => { if (ks.length > max) ks.slice(0, ks.length - max).forEach(k => c.delete(k)); });
  }
  return res;
}

self.addEventListener('fetch', e => {
  const r = e.request; if (r.method !== 'GET') return;
  const u = new URL(r.url);
  if (r.mode === 'navigate' && u.origin === location.origin && /(\/|\.html)$/.test(u.pathname)) { e.respondWith(shell(e)); return; }
  if (u.origin === location.origin && /(\.module\.min\.js|edinburgh3d\.json)$/.test(u.pathname)) { e.respondWith(cacheFirst(SHELL, r, 0, false).catch(() => fetch(r))); return; }
  if (u.origin === location.origin) { e.respondWith(caches.match(r, {ignoreSearch:true}).then(h => h || fetch(r))); return; }
  if (u.hostname === 'cdn.jsdelivr.net' || u.hostname === 'unpkg.com') { e.respondWith(cacheFirst(CDN, r, 0, true)); return; }
  if (u.hostname === 'covers.openlibrary.org' || u.hostname === 'books.google.com' || u.hostname.endsWith('.googleusercontent.com')) {
    e.respondWith(cacheFirst(IMG, r, 400).catch(() => fetch(r)));
  }
});

// Rappels de lecture : le serveur Signet envoie un signal (sans contenu) à l'heure choisie ;
// le texte est préparé par l'appli dans le cache, d'après le livre en cours et la série.
self.addEventListener('push', e => {
  e.waitUntil((async () => {
    let d = {}; try { d = e.data ? e.data.json() : {}; } catch(_) { d = {}; }
    if (!d.body) {
      try {
        const hit = await caches.match(new URL('./__remind', self.registration.scope).href, {cacheName:META});
        const m = hit ? await hit.json() : null;
        if (m && Array.isArray(m.bodies) && m.bodies.length) { const i = new Date().getDate() % m.bodies.length; d = {title:m.title || 'Signet', body:m.bodies[Math.min(i, m.bodies.length - 1)]}; if (m.bodies.length > 2) d.body = m.bodies[0]; }
      } catch(_) {}
    }
    await self.registration.showNotification(d.title || 'Signet', {body:d.body || 'Un chapitre ce soir ? Le grimoire veille.', icon:'./icon-192.png', badge:'./icon-192.png', tag:d.tag || 'signet', data:{url:d.url || './'}});
  })());
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || './', self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({type:'window', includeUncontrolled:true}).then(cs => { const c = cs.find(x => x.url.startsWith(self.registration.scope)); return c ? c.focus() : self.clients.openWindow(url); }));
});
